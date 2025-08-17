//
//  BestGuessProducer.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 13/08/2025.
//

import Foundation

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
        
        dprint(debug, "—— posMap ——")
        if debug {
            for j in 0..<n {
                let line = posSeen[j].sorted().joined(separator: " ")
                dprint(true, "posMap[\(j)] = \(line)")
            }
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
        
        // 3) Count greens already present (consume allowance at index-level).
        var greenCount: [String: Int] = [:]
        for j in 0..<n {
            for key in posSeen[j] {
                let parts = key.split(separator: "|")
                guard parts.count == 2 else { continue }
                if parts[1] == "G" {
                    greenCount[String(parts[0]), default: 0] += 1
                }
            }
        }
        dprint(debug, "greenCount = \(greenCount)")
        
        // 3b) Extra tallies for multi-occurrence handling:
        //     - greenSeen[L] = how many green positions for letter L (any row)
        //     - minOcc[L]    = LOWER BOUND on true occurrences of L implied by history:
        //                      max over rows of (#G + #Y) for L in that row
        //     - yellowCount[L] = total times L appeared yellow across all rows
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
                    case .exactMatch:
                        colored[ch, default: 0] += 1
                    case .partialMatch:
                        colored[ch, default: 0] += 1
                        yellowCount[ch, default: 0] += 1
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
        
        // 4) Build candidates per index from posSeen:
        //    - If any GREEN at j, include green(s) AND yellows only when:
        //        a) history proves more copies are needed beyond the greens we already have, OR
        //        b) it’s a lonely-yellow letter (never green anywhere, exactly one Y overall).
        //    - Else include all Y at j with residual > 0 (cap - greens) and all X (dedup by char).
        func parse(_ key: String) -> Guess? {
            let parts = key.split(separator: "|")
            guard parts.count == 2 else { return nil }
            let ch = String(parts[0])
            guard ch.count == 1 else { return nil } // drop garbage multi-char tokens
            switch parts[1] {
            case "G": return (ch, .exactMatch)
            case "Y": return (ch, .partialMatch)
            case "X": return (ch, .noMatch)
            default:  return nil
            }
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
                        let residual = (cap[g.char] ?? Int.max) - (greenCount[g.char] ?? 0)
                        if residual > 0 { yellows.append(g) }
                    }
                case .noMatch:
                    grays.append(g)
                default: break
                }
            }
            
            if !greens.isEmpty {
                // ✅ Keep greens; keep Y at this index only if history requires extra copies
                //    or it is a lonely-yellow (never went green anywhere and appears yellow once overall).
                var list = greens.sorted { $0.char < $1.char }
                
                for y in yellows.sorted(by: { $0.char < $1.char }) {
                    let needExtraCopy = (minOcc[y.char] ?? 0) > (greenSeen[y.char] ?? 0)
                    let lonelyYellow = !greenLetters.contains(y.char) && (yellowCount[y.char] == 1)
                    if needExtraCopy || lonelyYellow {
                        list.append(y)
                    }
                }
                candidates[j] = list
            } else {
                var list = yellows.sorted { $0.char < $1.char }
                // Add grays (dedupe by char)
                var seenGray = Set<String>()
                for g in grays.sorted(by: { $0.char < $1.char }) {
                    if seenGray.insert(g.char).inserted { list.append(g) }
                }
                if list.isEmpty {
                    dprint(true, "ERROR: no history-derived candidates at index \(j). Returning [].")
                    return []
                }
                candidates[j] = list
            }
        }
        
        dprint(debug, "—— candidates ——")
        if debug {
            for j in 0..<n {
                let line = candidates[j].map { "\($0.char)\(tag($0.color))" }.joined(separator: " ")
                dprint(true, "candidates[\(j)] = [\(line)]")
            }
        }
        
        // 5) DFS enumerate all rows with caps; Y/G consume cap, X does not.
        var results: [[Guess]] = []
        var seenRows = Set<String>()
        var used: [String: Int] = [:]
        var row: [Guess] = Array(repeating: ("", .noGuess), count: n)
        
        // extra per-row state
        var usedYG: [String: Int] = [:]     // Y/G placed counts for this row
        var usedX:  [String: Int] = [:]     // keep X duplicates in check
        
        func dfs(_ j: Int) {
            if j == n {
                // keep rows that have at least one Y or G
                if row.contains(where: { $0.color == .partialMatch || $0.color == .exactMatch }) {
                    let key = rowKey(row)
                    if seenRows.insert(key).inserted { results.append(row) }
                }
                return
            }
            
            let opts = candidates[j]
            if opts.isEmpty { return } // no blank fallback; every index must have history
            
            for g in opts {
                switch g.color {
                case .noMatch:
                    // 🔓 Allow gray together with Y/G of same letter in a single row (valid Wordle duplicate semantics).
                    //    We still limit gray spam per letter to 1 to avoid explosion; raise if needed.
                    if (usedX[g.char] ?? 0) >= 1 { continue }
                    
                    row[j] = g
                    usedX[g.char, default: 0] += 1
                    dfs(j + 1)
                    usedX[g.char]! -= 1
                    if usedX[g.char] == 0 { usedX.removeValue(forKey: g.char) }
                    
                case .partialMatch, .exactMatch:
                    // cap enforcement for true occurrences (Y/G)
                    let limit = cap[g.char] ?? Int.max
                    if (used[g.char] ?? 0) + 1 > limit { continue }
                    
                    row[j] = g
                    used[g.char, default: 0] += 1
                    usedYG[g.char, default: 0] += 1
                    dfs(j + 1)
                    usedYG[g.char]! -= 1
                    if usedYG[g.char] == 0 { usedYG.removeValue(forKey: g.char) }
                    used[g.char]! -= 1
                    
                default:
                    continue
                }
            }
        }
        
        dfs(0)
        dprint(debug, "rows found before entropy = \(results.count)")
        if results.isEmpty { return [] }
        
        // 6) Entropy scoring (ignores grays; G weighs more than Y). Keep best rows.
        func weight(_ c: CharColor) -> Double { c == .exactMatch ? 3.0 : 1.0 }
        var denom = Array(repeating: 0.0, count: n)
        for j in 0..<n {
            var sum = 0.0
            var uniq = Set<String>()
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
        
        if debug {
            dprint(true, "—— entropy per row ——")
            for (r, e) in scored { dprint(true, "\(rowPretty(r)) | H=\(String(format: "%.4f", e))") }
        }
        
        let bestScore = scored.map { $0.e }.max() ?? -Double.infinity
        var best = scored.filter { $0.e == bestScore }.map { $0.row }
        
        // Ties: more greens first, then stable key.
        func greensCount(_ r: [Guess]) -> Int { r.reduce(0) { $0 + ($1.color == .exactMatch ? 1 : 0) } }
        best.sort {
            let ga = greensCount($0), gb = greensCount($1)
            if ga != gb { return ga > gb }
            return rowKey($0) < rowKey($1)
        }
        
        dprint(debug, "max entropy = \(String(format: "%.4f", bestScore))")
        dprint(debug, "rows kept = \(best.count)")
        if debug { for r in best { dprint(true, "KEEP \(rowPretty(r))") } }
        
        return best
    }
    
    // MARK: internals
    
    private func computeCapsAndBans(
        n: Int,
        lastIdx: Int,
        matrix: [[String]],
        colors: [[CharColor]],
        aiMatrix: [[String]],
        aiColors: [[CharColor]]
    ) -> ([String: Int], Set<String>) {
        var perRowMaxColored: [String: Int] = [:] // soft cap = max(G+Y) seen in any single row
        var cap: [String: Int] = [:]              // hard cap when gray+colored appear in same row
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
                // strict cap: same row has gray + colored ⇒ cap ≤ colored
                if let bCnt = b[ch], bCnt > 0, colored > 0 {
                    cap[ch] = min(cap[ch] ?? Int.max, colored)
                }
            }
        }
        var banned = Set<String>()
        for ch in grayOnlySomeRow where !everColored.contains(ch) {
            banned.insert(ch)
            cap[ch] = 0
        }
        // IMPORTANT: never widen cap beyond the per-row maximum colored
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
    private func tag(_ c: CharColor) -> String {
        if c == .exactMatch { return "G" }
        if c == .partialMatch { return "Y" }
        if c == .noMatch { return "X" }
        return "_"
    }
    
    // Strict single-letter normalizer
    @inline(__always)
    private func normSingleLower(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ch = t.first else { return " " }
        return String(ch).lowercased()
    }
    
    // Keep signature, but always normalize to one letter
    @inline(__always)
    private func normAtPosLower(_ s: String, _ j: Int, _ lastIdx: Int) -> String {
        return normSingleLower(s)
    }
    
    @inline(__always)
    private func lettersRow(_ rows: [[String]], _ i: Int, _ n: Int) -> [String] {
        guard i < rows.count else { return Array(repeating: " ", count: n) }
        let r = rows[i]
        return r.count >= n ? Array(r.prefix(n)) : (r + Array(repeating: " ", count: n - r.count))
    }
    
    @inline(__always)
    private func colorsRow(_ rows: [[CharColor]], _ i: Int, _ n: Int) -> [CharColor] {
        guard i < rows.count else { return Array(repeating: .noGuess, count: n) }
        let r = rows[i]
        return r.count >= n ? Array(r.prefix(n)) : (r + Array(repeating: .noGuess, count: n - r.count))
    }
    
    @inline(__always)
    private func rowKey(_ row: [Guess]) -> String {
        var out = ""
        out.reserveCapacity(row.count * 4)
        for g in row {
            let ch = g.char.lowercased()
            let t = tag(g.color)
            out.append(ch)
            out.append("|")
            out.append(contentsOf: t)
            out.append(";")
        }
        return out
    }
    
    @inline(__always)
    private func rowPretty(_ row: [Guess]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(row.count)
        for (idx, g) in row.enumerated() {
            parts.append("\(idx):\(g.char)\(tag(g.color))")
        }
        return parts.joined(separator: " ")
    }
    
    @inline(__always)
    private func dprint(_ enabled: Bool, _ s: @autoclosure () -> String) {
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
        
        @inline(__always)
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
        
        @inline(__always)
        func greensCount(_ row: [Guess]) -> Int {
            row.reduce(0) { $0 + ($1.color == .exactMatch ? 1 : 0) }
        }
        
        @inline(__always)
        func stableKey(_ row: [Guess]) -> String {
            var out = ""
            out.reserveCapacity(n * 3)
            for g in row {
                out += g.char.lowercased()
                out += (g.color == .exactMatch ? "G" : (g.color == .partialMatch ? "Y" : "X"))
                out += ";"
            }
            return out
        }
        
        var best = rows[0]
        var bestScore = entropyScore(best)
        var bestGreens = greensCount(best)
        var bestKey = stableKey(best)
        
        for i in 1..<rows.count {
            let r = rows[i]
            let e = entropyScore(r)
            if e > bestScore {
                best = r; bestScore = e; bestGreens = greensCount(r); bestKey = stableKey(r)
                continue
            }
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
