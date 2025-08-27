//
//  BestGuessProducer.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 13/08/2025.
//

import Foundation

typealias BestGuess = (index: Int, colordLetters: [Guess])
typealias Guess = (char: String, color: CharColor)

final class BestGuessProducerProvider: Singleton {
    private lazy var instance = BestGuessProducer.shared
    static let guesser = shared.instance
    override private init() {}
}

// MARK: - BestGuessProducer

final class BestGuessProducer: Singleton {
    @available(*, unavailable, message: "Cannot be initialized through the constructor")
    private override init() { super.init() }
    
    // MARK: New sparse API (preferred)
    // Returns only indices that have something to show, enforcing:
    // 1) Prefer G alone: lock greens to their positions.
    // 2) Prefer Y alone: rehome Y’s to free slots (no G) so each such slot has at most one Y.
    // 3) If a Y can’t be rehomed, allow placing it with a G; if still impossible, keep at one of its original Y indices.
    func perIndexCandidatesSparse(
        matrix: [[String]],
        colors: [[CharColor]],
        aiMatrix: [[String]],
        aiColors: [[CharColor]],
        debug: Bool = false
    ) -> [BestGuess] {
        
        let n: Int = (
            colors.first?.count ??
            aiColors.first?.count ??
            matrix.first?.count ??
            aiMatrix.first?.count ?? 5
        )
        let lastIdx = max(0, n - 1)
        let rowsCount = max(matrix.count, max(colors.count, max(aiMatrix.count, aiColors.count)))
        
        // 1) Collect ALL (char,color) pairs seen at EACH index from player + AI, including gray.
        var posSeen: [Set<String>] = Array(repeating: Set<String>(), count: n) // keys "e|G", "r|Y", "t|X"
        for i in 0..<rowsCount {
            let pL = lettersRow(matrix, i, n)
            let pC = colorsRow(colors, i, n)
            let aL = lettersRow(aiMatrix, i, n)
            let aC = colorsRow(aiColors, i, n)
            for j in 0..<n {
                let pc = pC[j]
                if pc != .noGuess {
                    let ch = normAtPosLower(pL[j], j, lastIdx)
                    if !isEmptyToken(ch) { posSeen[j].insert(ch + "|" + tag(pc)) }
                }
                let ac = aC[j]
                if ac != .noGuess {
                    let ch = normAtPosLower(aL[j], j, lastIdx)
                    if !isEmptyToken(ch) { posSeen[j].insert(ch + "|" + tag(ac)) }
                }
            }
        }
        
        // 2) Caps and bans from history (letter-level), and tallies we need later.
        let (cap, banned) = computeCapsAndBans(
            n: n,
            lastIdx: lastIdx,
            matrix: matrix,
            colors: colors,
            aiMatrix: aiMatrix,
            aiColors: aiColors
        )
        
        // Greens by index; Y-forbidden positions per letter; original Y indices per letter
        var greensAt: [Int: Set<String>] = [:]        // index -> set of green letters (normally one)
        var yForbidden: [String: Set<Int>] = [:]      // letter -> indexes where it was Y (so not allowed there)
        var yOriginalAt: [String: Set<Int>] = [:]     // letter -> indexes where it appeared as Y (for fallback)
        var lettersPresent = Set<String>()            // letters known to be present (had any Y or G)
        
        for j in 0..<n {
            for key in posSeen[j] {
                let parts = key.split(separator: "|"); guard parts.count == 2 else { continue }
                let ch = String(parts[0]); let t = String(parts[1])
                switch t {
                case "G":
                    greensAt[j, default: []].insert(ch)
                    lettersPresent.insert(ch)
                case "Y":
                    yForbidden[ch, default: []].insert(j)
                    yOriginalAt[ch, default: []].insert(j)
                    lettersPresent.insert(ch)
                default:
                    break
                }
            }
        }
        
        // minOcc (needed occurrences overall), greenSeen (already satisfied by G)
        var greenSeen: [String:Int] = [:]
        var minOcc: [String:Int] = [:]
        do {
            var rows: [([String], [CharColor])] = []
            for i in 0..<min(matrix.count, colors.count)       { rows.append((matrix[i],   colors[i])) }
            for i in 0..<min(aiMatrix.count, aiColors.count)   { rows.append((aiMatrix[i], aiColors[i])) }
            for (lettersRow, colorsRow) in rows {
                let w = min(n, min(lettersRow.count, colorsRow.count))
                var colored: [String:Int] = [:]
                for j in 0..<w {
                    let ch = normSingleLower(lettersRow[j])
                    switch colorsRow[j] {
                    case .exactMatch:
                        colored[ch, default: 0] += 1
                        greenSeen[ch, default: 0] += 1
                    case .partialMatch:
                        colored[ch, default: 0] += 1
                    default: break
                    }
                }
                for (ch, c) in colored { minOcc[ch] = max(minOcc[ch] ?? 0, c) }
            }
        }
        
        // 3) Y "need" per letter (bounded by cap)
        var need: [String:Int] = [:]
        for ch in lettersPresent {
            let must = minOcc[ch] ?? 0
            let haveG = greenSeen[ch] ?? 0
            let maxCap = cap[ch] ?? Int.max
            let still = max(0, min(must, maxCap) - haveG)
            if still > 0 { need[ch] = still }
        }
        
        // Helpful: for any letter, which indices have that SAME letter as green?
        func indicesWithGreen(_ ch: String) -> Set<Int> {
            var res: Set<Int> = []
            for (idx, set) in greensAt where set.contains(ch) { res.insert(idx) }
            return res
        }
        
        // 4) Assign Y's
        let greenOccupied = Set(greensAt.keys)
        var takenYIndex = Set<Int>()           // ensure “Y alone” where possible (one Y per free index)
        var assignY: [Int:[String]] = [:]      // index -> [letters placed as Y here]
        
        struct NeedItem { let ch: String; let options: [Int] }
        
        // Pass A: avoid green indices (place Y in free slots only)
        var passA: [NeedItem] = []
        for (ch, k) in need {
            guard !banned.contains(ch) else { continue }
            let forb = (yForbidden[ch] ?? []).union(indicesWithGreen(ch)) // <- never Y where same letter is G
            let opts = Array(Set(0..<n).subtracting(greenOccupied).subtracting(forb)).sorted()
            for _ in 0..<k { passA.append(NeedItem(ch: ch, options: opts)) }
        }
        passA.sort { $0.options.count < $1.options.count } // constrained first
        var remaining: [String:Int] = [:]
        for item in passA {
            if let idx = item.options.first(where: { !takenYIndex.contains($0) }) {
                assignY[idx, default: []].append(item.ch)
                takenYIndex.insert(idx)
            } else {
                remaining[item.ch, default: 0] += 1
            }
        }
        
        // Pass B: allow green indices too (still try to keep 1 Y per index), but never if same letter is G there
        if !remaining.isEmpty {
            var passB: [NeedItem] = []
            for (ch, k) in remaining {
                let forb = (yForbidden[ch] ?? []).union(indicesWithGreen(ch)) // <- same safeguard
                let opts = Array(Set(0..<n).subtracting(forb)).sorted()
                for _ in 0..<k { passB.append(NeedItem(ch: ch, options: opts)) }
            }
            passB.sort { $0.options.count < $1.options.count }
            remaining.removeAll()
            
            for item in passB {
                if let idx = item.options.first(where: { !takenYIndex.contains($0) }) {
                    assignY[idx, default: []].append(item.ch)
                    takenYIndex.insert(idx)
                } else {
                    remaining[item.ch, default: 0] += 1
                }
            }
        }
        
        // Pass C (fallback): keep at original Y indices (may co-exist with G and other Y’s),
        // BUT NEVER place Y where the same letter is G.
        if !remaining.isEmpty {
            for (ch, k) in remaining {
                var homes = Array((yOriginalAt[ch] ?? []).subtracting(indicesWithGreen(ch)))
                if homes.isEmpty { continue } // nowhere valid to show; skip for display
                homes.sort()
                // Distribute round-robin over original Y indices
                for t in 0..<k {
                    let idx = homes[t % homes.count]
                    assignY[idx, default: []].append(ch)
                }
            }
        }
        
        // 5) Build sparse output; indices with nothing are omitted.
        var out: [(index: Int, colordLetters: [Guess])] = []
        out.reserveCapacity(n)
        
        for j in 0..<n {
            var bucket: [Guess] = []
            // Lock greens (prefer G alone)
            if let gset = greensAt[j], !gset.isEmpty {
                for ch in gset.sorted() where !banned.contains(ch) {
                    bucket.append((ch, .exactMatch))
                }
            }
            // Assigned Y for this index (either free placement or fallback)
            if let ys = assignY[j], !ys.isEmpty {
                // If a same-letter green exists here, it was filtered earlier; keep that invariant.
                for ch in ys.sorted() where !banned.contains(ch) {
                    bucket.append((ch, .partialMatch))
                }
            }
            if !bucket.isEmpty {
                out.append((index: j, colordLetters: bucket))
            }
        }
        
        if debug {
            dprint(true, "— perIndexCandidatesSparse —")
            for item in out {
                let pretty = item.colordLetters.map { "\($0.char)\(tag($0.color))" }.joined(separator: " ")
                dprint(true, "[\(item.index)] -> [\(pretty)]")
            }
        }
        
        return out
    }
    
    // MARK: Existing dense API (kept for compatibility)
    // Returns [[Guess]] aligned by index; indices with no letters return an empty array.
    func allBestGuesses(
        matrix: [[String]],
        colors: [[CharColor]],
        aiMatrix: [[String]],
        aiColors: [[CharColor]],
        debug: Bool = false
    ) -> [[Guess]] {
        let n: Int = (
            colors.first?.count ??
            aiColors.first?.count ??
            matrix.first?.count ??
            aiMatrix.first?.count ?? 5
        )
        let lastIdx = max(0, n - 1)
        
        // 1) Collect ALL (char,color) pairs seen at EACH index from player + AI, including gray.
        var posSeen: [Set<String>] = Array(repeating: Set<String>(), count: n) // keys "e|G", "r|Y", "t|X"
        let rowsCount = max(matrix.count, max(colors.count, max(aiMatrix.count, aiColors.count)))
        for i in 0..<rowsCount {
            let pL = lettersRow(matrix, i, n)
            let pC = colorsRow(colors, i, n)
            let aL = lettersRow(aiMatrix, i, n)
            let aC = colorsRow(aiColors, i, n)
            for j in 0..<n {
                let pc = pC[j]
                if pc != .noGuess {
                    let ch = normAtPosLower(pL[j], j, lastIdx)
                    if !isEmptyToken(ch) { posSeen[j].insert(ch + "|" + tag(pc)) }
                }
                let ac = aC[j]
                if ac != .noGuess {
                    let ch = normAtPosLower(aL[j], j, lastIdx)
                    if !isEmptyToken(ch) { posSeen[j].insert(ch + "|" + tag(ac)) }
                }
            }
        }
        
        if debug {
            dprint(true, "—— posMap ——")
            for j in 0..<n { dprint(true, "posMap[\(j)] = \(posSeen[j].sorted().joined(separator: " "))") }
        }
        
        // 2) Caps and bans from history (letter-level).
        let (cap, banned) = computeCapsAndBans(
            n: n,
            lastIdx: lastIdx,
            matrix: matrix,
            colors: colors,
            aiMatrix: aiMatrix,
            aiColors: aiColors
        )
        dprint(debug, "—— caps/bans ——")
        dprint(debug, "cap = \(cap)")
        dprint(debug, "banned = \(Array(banned).sorted())")
        
        // === NEW: yForbidden (indices where each letter was marked Y) ===
        var yForbidden: [String: Set<Int>] = [:]
        for j in 0..<n {
            for key in posSeen[j] {
                let parts = key.split(separator: "|"); guard parts.count == 2 else { continue }
                if parts[1] == "Y" {
                    yForbidden[String(parts[0]), default: []].insert(j)
                }
            }
        }
        
        // 3) Count greens already present (consume allowance at index-level).
        var greenCount: [String: Int] = [:]
        for j in 0..<n {
            for key in posSeen[j] {
                let parts = key.split(separator: "|")
                guard parts.count == 2 else { continue }
                if parts[1] == "G" { greenCount[String(parts[0]), default: 0] += 1 }
            }
        }
        
        // Tallies for multi-occur handling
        var greenSeen: [String:Int] = [:]
        for set in posSeen {
            for key in set {
                let p = key.split(separator: "|"); guard p.count == 2 else { continue }
                if p[1] == "G" { greenSeen[String(p[0]), default: 0] += 1 }
            }
        }
        let greenLetters = Set(greenSeen.keys)
        var minOcc: [String:Int] = [:]
        var yellowCount: [String:Int] = [:]
        do {
            var rows: [([String], [CharColor])] = []
            for i in 0..<min(matrix.count, colors.count)       { rows.append((matrix[i],   colors[i])) }
            for i in 0..<min(aiMatrix.count, aiColors.count)   { rows.append((aiMatrix[i], aiColors[i])) }
            for (lettersRow, colorsRow) in rows {
                let w = min(n, min(lettersRow.count, colorsRow.count))
                var colored: [String:Int] = [:]
                for j in 0..<w {
                    let ch = normSingleLower(lettersRow[j])
                    switch colorsRow[j] {
                    case .exactMatch:   colored[ch, default: 0] += 1
                    case .partialMatch: colored[ch, default: 0] += 1; yellowCount[ch, default: 0] += 1
                    default: break
                    }
                }
                for (ch, c) in colored { minOcc[ch] = max(minOcc[ch] ?? 0, c) }
            }
        }
        if debug {
            dprint(true, "greenSeen = \(greenSeen)")
            dprint(true, "minOcc = \(minOcc)")
            dprint(true, "yellowCount = \(yellowCount)")
        }
        
        // 4) Build candidates per index from posSeen (+ inferred Y’s).
        func parse(_ key: String) -> Guess? {
            let parts = key.split(separator: "|")
            guard parts.count == 2 else { return nil }
            let ch = String(parts[0])
            guard ch.count == 1 else { return nil }
            switch parts[1] {
            case "G": return (ch, .exactMatch)
            case "Y": return (ch, .partialMatch)
            case "X": return (ch, .noMatch)
            default:  return nil
            }
        }
        
        // residual helper
        @inline(__always)
        func residual(_ ch: String) -> Int {
            let lim = cap[ch] ?? Int.max
            let need = min(minOcc[ch] ?? 0, lim)
            let g    = greenSeen[ch] ?? 0
            return max(0, need - g)
        }
        
        var candidates: [[Guess]] = Array(repeating: [], count: n)
        for j in 0..<n {
            var greens: [Guess] = []
            var yellows: [Guess] = []
            var grays: [Guess] = []
            for key in posSeen[j] {
                guard let g = parse(key) else { continue }
                switch g.color {
                case .exactMatch:
                    if !banned.contains(g.char) { greens.append(g) }
                case .partialMatch:
                    if !banned.contains(g.char) {
                        let res = (cap[g.char] ?? Int.max) - (greenCount[g.char] ?? 0)
                        if res > 0 { yellows.append(g) }
                    }
                case .noMatch:
                    grays.append(g)
                default: break
                }
            }
            
            // === NEW: add inferred Y’s when there is no green at this index ===
            if greens.isEmpty {
                let seenYHere = Set(yellows.map { $0.char })
                for (ch, _) in minOcc {
                    if banned.contains(ch) { continue }
                    if residual(ch) <= 0 { continue }
                    if seenYHere.contains(ch) { continue }
                    if (yForbidden[ch] ?? []).contains(j) { continue } // Wordle semantics: Y means "not here"
                    yellows.append((ch, .partialMatch))
                }
            }
            // === end NEW ===
            
            if !greens.isEmpty {
                // ✅ Keep greens; also keep Y of other letters only when informative.
                var list = greens.sorted { $0.char < $1.char }
                let greenChars = Set(greens.map { $0.char })
                for y in yellows.sorted(by: { $0.char < $1.char }) where !greenChars.contains(y.char) {
                    let needExtraCopy = residual(y.char) > 0
                    let lonelyYellow  = !greenLetters.contains(y.char) && (yellowCount[y.char] == 1)
                    if needExtraCopy || lonelyYellow {
                        list.append(y)
                    }
                }
                candidates[j] = list
            } else {
                var list = yellows.sorted { $0.char < $1.char }
                var seenGray = Set<String>()
                for g in grays.sorted(by: { $0.char < $1.char }) {
                    if seenGray.insert(g.char).inserted { list.append(g) }
                }
                candidates[j] = list
            }
        }
        
        if debug {
            dprint(true, "—— candidates ——")
            for j in 0..<n {
                let line = candidates[j].map { "\($0.char)\(tag($0.color))" }.joined(separator: " ")
                dprint(true, "candidates[\(j)] = [\(line)]")
            }
        }
        
        // 5) DFS enumerate with caps; if any green exists at an index, restrict to G only.
        var results: [[Guess]] = []
        var seenRows = Set<String>()
        var used: [String: Int] = [:]
        var row: [Guess] = Array(repeating: ("", .noGuess), count: n)
        var usedYG: [String: Int] = [:]
        var usedX:  [String: Int] = [:]
        
        func dfs(_ j: Int) {
            if j == n {
                if row.contains(where: { $0.color == .partialMatch || $0.color == .exactMatch }) {
                    let key = rowKey(row)
                    if seenRows.insert(key).inserted { results.append(row) }
                }
                return
            }
            let rawOpts = candidates[j]
            if rawOpts.isEmpty { return }
            let opts = rawOpts.contains(where: { $0.color == .exactMatch })
            ? rawOpts.filter { $0.color == .exactMatch }
            : rawOpts
            
            for g in opts {
                switch g.color {
                case .noMatch:
                    if (usedX[g.char] ?? 0) >= 1 { continue }
                    row[j] = g
                    usedX[g.char, default: 0] += 1
                    dfs(j + 1)
                    usedX[g.char]! -= 1; if usedX[g.char] == 0 { usedX.removeValue(forKey: g.char) }
                case .partialMatch, .exactMatch:
                    let limit = cap[g.char] ?? Int.max
                    if (used[g.char] ?? 0) + 1 > limit { continue }
                    row[j] = g
                    used[g.char, default: 0] += 1
                    usedYG[g.char, default: 0] += 1
                    dfs(j + 1)
                    usedYG[g.char]! -= 1; if usedYG[g.char] == 0 { usedYG.removeValue(forKey: g.char) }
                    used[g.char]! -= 1
                default: continue
                }
            }
        }
        dfs(0)
        if results.isEmpty { return Array(repeating: [], count: n) }
        
        // 6) Entropy scoring (G weight > Y)
        func weight(_ c: CharColor) -> Double { c == .exactMatch ? 3.0 : 1.0 }
        var denom = Array(repeating: 0.0, count: n)
        
        for j in 0..<n {
            var sum = 0.0, uniq = Set<String>()
            for g in candidates[j] where g.color == .partialMatch || g.color == .exactMatch {
                let k = g.char + "|" + tag(g.color)
                if uniq.insert(k).inserted { sum += weight(g.color) }
            }
            denom[j] = max(sum, 1.0)
        }
        
        func entropy(_ r: [Guess]) -> Double {
            var s = 0.0
            for j in 0..<n {
                let g = r[j]
                guard g.color == .partialMatch || g.color == .exactMatch else { continue }
                s += -log2(weight(g.color) / denom[j])
            }
            return s
        }
        
        let scored: [(row: [Guess], e: Double)] = results.map { ($0, entropy($0)) }
        let bestScore = scored.map { $0.e }.max() ?? -Double.infinity
        var best = scored.filter { $0.e == bestScore }.map { $0.row }
        
        func greensCount(_ r: [Guess]) -> Int { r.reduce(0) { $0 + ($1.color == .exactMatch ? 1 : 0) } }
        
        best.sort {
            let ga = greensCount($0), gb = greensCount($1)
            if ga != gb { return ga > gb }
            return rowKey($0) < rowKey($1)
        }
        
        // Convert to aligned-by-index [[Guess]]
        var dense: [[Guess]] = Array(repeating: [], count: n)
        if let top = best.first {
            for (j, g) in top.enumerated() where g.color != .noGuess {
                dense[j].append(g)
            }
        }
        return dense
    }
    
    // MARK: - Internals (shared by both APIs)
    
    private func computeCapsAndBans(
        n: Int,
        lastIdx: Int,
        matrix: [[String]],
        colors: [[CharColor]],
        aiMatrix: [[String]],
        aiColors: [[CharColor]]
    ) -> ([String: Int], Set<String>) {
        var perRowMaxColored: [String: Int] = [:]
        var cap: [String: Int] = [:]
        var everColored = Set<String>()
        var grayOnlySomeRow = Set<String>()
        var rows: [([String], [CharColor])] = []
        for i in 0..<min(matrix.count, colors.count) { rows.append((matrix[i], colors[i])) }
        for i in 0..<min(aiMatrix.count, aiColors.count) { rows.append((aiMatrix[i], aiColors[i])) }
        for (lettersRow, colorsRow) in rows {
            let w = min(n, min(lettersRow.count, colorsRow.count))
            var g: [String: Int] = [:]
            var y: [String: Int] = [:]
            var b: [String: Int] = [:]
            for j in 0..<w {
                let ch = normSingleLower(lettersRow[j])
                switch colorsRow[j] {
                case .exactMatch:   g[ch, default: 0] += 1
                case .partialMatch: y[ch, default: 0] += 1
                case .noMatch:      b[ch, default: 0] += 1
                default: break
                }
            }
            let touched = Set(g.keys).union(y.keys).union(b.keys)
            for ch in touched {
                let colored = (g[ch] ?? 0) + (y[ch] ?? 0)
                if colored > 0 {
                    everColored.insert(ch)
                    perRowMaxColored[ch] = max(perRowMaxColored[ch] ?? 0, colored)
                } else if (b[ch] ?? 0) > 0 {
                    grayOnlySomeRow.insert(ch)
                }
                if let bCnt = b[ch], bCnt > 0, colored > 0 {
                    cap[ch] = min(cap[ch] ?? Int.max, colored)
                }
            }
        }
        var banned = Set<String>()
        for ch in grayOnlySomeRow where !everColored.contains(ch) {
            banned.insert(ch); cap[ch] = 0
        }
        for (ch, m) in perRowMaxColored {
            if let c = cap[ch] { cap[ch] = min(c, m) } else { cap[ch] = m }
        }
        return (cap, banned)
    }
    
    // MARK: helpers
    
    @inline(__always)
    private func isEmptyToken(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    @inline(__always)
    fileprivate func tag(_ c: CharColor) -> String {
        if c == .exactMatch { return "G" }
        if c == .partialMatch { return "Y" }
        if c == .noMatch     { return "X" }
        return "_"
    }
    
    // strict single-letter normalizer
    @inline(__always)
    fileprivate func normSingleLower(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ch = t.first else { return " " }
        // collapse Hebrew finals to base
        switch ch {
        case "ך": return "כ"
        case "ם": return "מ"
        case "ן": return "נ"
        case "ף": return "פ"
        case "ץ": return "צ"
        default:  return String(ch).lowercased()
        }
    }
    
    // position-normalizer (kept for API symmetry)
    @inline(__always)
    fileprivate func normAtPosLower(_ s: String, _ j: Int, _ lastIdx: Int) -> String {
        return normSingleLower(s)
    }
    
    @inline(__always)
    fileprivate func lettersRow(_ rows: [[String]], _ i: Int, _ n: Int) -> [String] {
        guard i < rows.count else { return Array(repeating: " ", count: n) }
        let r = rows[i]
        return r.count >= n ? Array(r.prefix(n)) : (r + Array(repeating: " ", count: n - r.count))
    }
    @inline(__always)
    fileprivate func colorsRow(_ rows: [[CharColor]], _ i: Int, _ n: Int) -> [CharColor] {
        guard i < rows.count else { return Array(repeating: .noGuess, count: n) }
        let r = rows[i]
        return r.count >= n ? Array(r.prefix(n)) : (r + Array(repeating: .noGuess, count: n - r.count))
    }
    @inline(__always)
    fileprivate func rowKey(_ row: [Guess]) -> String {
        var out = ""
        out.reserveCapacity(row.count * 4)
        for g in row {
            out.append(g.char.lowercased()); out.append("|"); out.append(contentsOf: tag(g.color)); out.append(";")
        }
        return out
    }
    @inline(__always)
    fileprivate func rowPretty(_ row: [Guess]) -> String {
        var parts: [String] = []; parts.reserveCapacity(row.count)
        for (idx, g) in row.enumerated() { parts.append("\(idx):\(g.char)\(tag(g.color))") }
        return parts.joined(separator: " ")
    }
    @inline(__always)
    fileprivate func dprint(_ enabled: Bool, _ s: @autoclosure () -> String) {
        if enabled { print(s()) }
    }
}

// MARK: - Best-entropy single row (unchanged)

extension BestGuessProducer {
    func bestEntropyRow(from rows: [[Guess]]) -> [Guess]? {
        guard let first = rows.first else { return nil }
        let n = first.count
        @inline(__always) func weight(_ c: CharColor) -> Double { c == .exactMatch ? 3.0 : 1.0 }
        
        var denom = [Double](repeating: 0, count: n)
        for j in 0..<n {
            var seen = Set<String>()
            var sum = 0.0
            for row in rows {
                let g = row[j]
                guard g.color == .partialMatch || g.color == .exactMatch else { continue }
                let key = g.char.lowercased() + (g.color == .exactMatch ? "G" : "Y")
                if seen.insert(key).inserted { sum += weight(g.color) }
            }
            denom[j] = max(sum, 1e-9)
        }
        func entropyScore(_ row: [Guess]) -> Double {
            var s = 0.0
            for j in 0..<n {
                let g = row[j]
                guard g.color == .partialMatch || g.color == .exactMatch else { continue }
                let p = weight(g.color) / denom[j]
                s += -log2(p)
            }
            return s
        }
        func greensCount(_ row: [Guess]) -> Int { row.reduce(0) { $0 + ($1.color == .exactMatch ? 1 : 0) } }
        func stableKey(_ row: [Guess]) -> String {
            var out = ""; out.reserveCapacity(n * 3)
            for g in row {
                out += g.char.lowercased()
                out += (g.color == .exactMatch ? "G" : (g.color == .partialMatch ? "Y" : "X"))
                out += ";"
            }
            return out
        }
        var best = rows[0]; var bestScore = entropyScore(best); var bestGreens = greensCount(best); var bestKey = stableKey(best)
        for i in 1..<rows.count {
            let r = rows[i]; let e = entropyScore(r)
            if e > bestScore { best = r; bestScore = e; bestGreens = greensCount(r); bestKey = stableKey(r); continue }
            if e == bestScore {
                let g = greensCount(r)
                if g > bestGreens || (g == bestGreens && stableKey(r) < bestKey) {
                    best = r; bestScore = e; bestGreens = g; bestKey = stableKey(r)
                }
            }
        }
        return best
    }
}
