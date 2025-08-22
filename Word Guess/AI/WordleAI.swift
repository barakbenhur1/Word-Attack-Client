//
//  WordleAI.swift
//  Word Zap / Word Guess
//

import Foundation
import CoreML
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Pretty trace

enum Fancy {
    static let reset  = "\u{001B}[0m"
    static let gray   = "\u{001B}[90m"
    static let blue   = "\u{001B}[34m"
    static let green  = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let mag    = "\u{001B}[35m"
    static let cyan   = "\u{001B}[36m"
    static let red    = "\u{001B}[31m"
}

enum Trace {
#if DEBUG
    static var enabled = true
#else
    static var enabled = false
#endif
    static func log(_ tag: String, _ s: @autoclosure () -> String, _ color: String = Fancy.gray) {
        guard enabled else { return }
        print("\(color)\(tag) \(s())\(Fancy.reset)")
    }
}

// MARK: - Public API

public typealias GuessHistory = (word: String, feedback: String)
public typealias AIDifficultyItem = (image: String, name: String)

public enum Language: String { case en, he }

public enum AIDifficulty {
    case easy, medium, hard, boss
    typealias RawValue = AIDifficultyItem
    public init?(rawValue: AIDifficultyItem) {
        switch rawValue {
        case ("easyAI", "Chad GPT"): self = .easy
        case ("mediumAI", "Hell 9000"): self = .medium
        case ("hardAI", "Spynet"): self = .hard
        case ("bossAI", "This Guy"): self = .boss
        default: fatalError()
        }
    }
    
    public var rawValue: AIDifficultyItem {
        switch self {
        case .easy: return ("easyAI", "Chad GPT")
        case .medium: return ("mediumAI", "Hell 9000")
        case .hard: return ("hardAI", "Spynet")
        case .boss: return ("bossAI", "This Guy")
        }
    }
    
    /// (temperature, topK)
    var params: (temperature: Float, topK: Int) {
        switch self {
        case .easy: return (0.70, 32)
        case .medium: return (0.40, 12)
        case .hard, .boss: return (0.00, 1)
        }
    }
}

public enum WordlePrompt {
    public static func make(from history: [GuessHistory]) -> String {
        guard !history.isEmpty else { return "" }
        return history.map { "\($0.word) \($0.feedback)" }.joined(separator: "\n") + "\n"
    }
}

// MARK: - Tiny LRU

private final class LRUCache<K: Hashable, V> {
    private var dict: [K:(value: V, tick: Int)] = [:]
    private let capacity: Int
    private var tick = 0
    init(capacity: Int) { self.capacity = max(1, capacity) }
    func get(_ k: K) -> V? {
        guard var e = dict[k] else { return nil }
        tick &+= 1; e.tick = tick; dict[k] = e; return e.value
    }
    func set(_ k: K, _ v: V) {
        tick &+= 1; dict[k] = (v, tick)
        if dict.count > capacity {
            var oldest: (K, Int)? = nil
            for (k, e) in dict where oldest == nil || e.tick < oldest!.1 { oldest = (k, e.tick) }
            if let key = oldest?.0 { dict.removeValue(forKey: key) }
        }
    }
}

// MARK: - Feather-weight tokenizer (BPE shim)

private protocol Tokenizing {
    var vocabSize: Int { get }
    func tokenString(for id: Int) -> String?
    func encode(_ text: String, addBOS: Bool) -> [Int]
    func decode(_ ids: [Int]) -> String
    func bos() -> Int?
    func eos() -> Int?
}

private struct Pair: Hashable { let a: String; let b: String }

final class BPETokenizer {
    private let idToToken: [Int:String]
    private let tokenToId: [String:Int]
    private let ranks: [Pair:Int]
    private let bosId: Int?
    private let eosId: Int?
    private let unkId: Int
    private let special: Set<String>
    
    var vocabSize: Int { idToToken.count }
    
    init(tokenizerJSON url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String:Any] else {
            throw NSError(domain: "Tokenizer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Bad tokenizer.json"])
        }
        
        var i2t: [Int:String] = [:], t2i: [String:Int] = [:]
        var pairRanks: [Pair:Int] = [:]
        var specials = Set<String>()
        
        if let model = root["model"] as? [String:Any] {
            if let vocab = model["vocab"] as? [String:Int] {
                for (tok, id) in vocab { i2t[id] = tok; t2i[tok] = id }
            }
            if let merges = model["merges"] as? [String] {
                for (rank, line) in merges.enumerated() {
                    let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    if parts.count == 2 {
                        pairRanks[Pair(a: String(parts[0]), b: String(parts[1]))] = rank
                    }
                }
            }
        }
        if let added = root["added_tokens"] as? [[String:Any]] {
            for a in added {
                if let tok = a["content"] as? String, let id = a["id"] as? Int {
                    i2t[id] = tok; t2i[tok] = id
                    if (a["special"] as? Bool) == true { specials.insert(tok) }
                }
            }
        }
        
        guard !i2t.isEmpty else {
            throw NSError(domain: "Tokenizer", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Empty vocab"])
        }
        
        self.idToToken = i2t
        self.tokenToId = t2i
        self.ranks = pairRanks
        self.special = specials.union(["<s>","</s>","<unk>"])
        self.bosId = t2i["<s>"]
        self.eosId = t2i["</s>"]
        self.unkId = t2i["<unk>"] ?? 0
    }
    
    func bos() -> Int? { bosId }
    func eos() -> Int? { eosId }
    func tokenString(for id: Int) -> String? { idToToken[id] }
    
    // Encode: NFKC + Metaspace + BPE
    func encode(_ text: String, addBOS: Bool = true) -> [Int] {
        var ids: [Int] = []
        if addBOS, let b = bosId { ids.append(b) }
        
        // NFKC normalization to match training
        let nfkc = text.precomposedStringWithCompatibilityMapping
        
        // Metaspace (▁) to mark spaces
        let pre = "▁" + nfkc.replacingOccurrences(of: " ", with: " ▁")
        
        for chunk in pre.split(separator: " ", omittingEmptySubsequences: false) {
            for tok in bpe(String(chunk)) {
                ids.append(tokenToId[tok] ?? unkId)
            }
        }
        return ids
    }
    
    // Decode: drop specials, replace metaspace with space, trim leading space
    func decode(_ ids: [Int]) -> String {
        var s = ""
        for id in ids {
            guard let tok = idToToken[id] else { continue }
            if special.contains(tok) { continue }
            s += tok
        }
        var out = s.replacingOccurrences(of: "▁", with: " ")
        if out.hasPrefix(" ") { out.removeFirst() }
        return out
    }
    
    // Greedy BPE merges
    private func bpe(_ word: String) -> [String] {
        var tokens = word.map { String($0) }
        if tokens.count <= 1 { return tokens }
        
        func bestPairRank() -> (pair: Pair, rank: Int, idxs: [Int])? {
            var best: (pair: Pair, rank: Int)? = nil
            var i = 0
            while i < tokens.count - 1 {
                let p = Pair(a: tokens[i], b: tokens[i+1])
                if let r = ranks[p] {
                    if best == nil || r < best!.rank { best = (p, r) }
                }
                i += 1
            }
            guard let b = best else { return nil }
            
            var idxs: [Int] = []
            var j = 0
            while j < tokens.count - 1 {
                if tokens[j] == b.pair.a && tokens[j+1] == b.pair.b { idxs.append(j); j += 2 }
                else { j += 1 }
            }
            return (b.pair, b.rank, idxs)
        }
        
        while let found = bestPairRank() {
            var newTokens: [String] = []
            var i = 0
            let idxSet = Set(found.idxs)
            while i < tokens.count {
                if i < tokens.count - 1, idxSet.contains(i) {
                    newTokens.append(tokens[i] + tokens[i+1]); i += 2
                } else {
                    newTokens.append(tokens[i]); i += 1
                }
            }
            if newTokens.count == tokens.count { break }
            tokens = newTokens
        }
        return tokens
    }
}

// MARK: - WordleAI

final class WordleAI: Singleton {
    public var useLangTags = true
    
    private let tokenizer: BPETokenizer
    private let prefill: MLModel?
    private let decode: MLModel?
    private let fallbackModel: MLModel?
    
    private struct Spec { let maxT: Int; let numL: Int; let vocab: Int; let padId: Int; let eosId: Int }
    private let spec: Spec
    
    private var idsMA: MLMultiArray
    private var maskMA: MLMultiArray
    private let tok1x1: MLMultiArray
    private var curLen = 0
    private var pastK: [MLMultiArray] = []
    private var pastV: [MLMultiArray] = []
    
    private let T_prefill: Int?
    private let T_decode:  Int?
    private let T_fallback: Int?
    
    private let logitsCache = LRUCache<[Int],[Float]>(capacity: 256)
    private let encodeCache  = LRUCache<String,[Int]>(capacity: 64)
    
    private let letterMapEN: [Int: Character]
    private let letterMapHE: [Int: Character]
    private let candidateEN: [Int]
    private let candidateHE: [Int]
    
    private let wordStringSetEN: Set<String>
    private let wordStringSetHE: Set<String>
    
    private let openerMinEntropy: Double = 1.55
    
    private var warmedUp = false
    
    fileprivate var needWarmup: Bool { !warmedUp }
    
    // MARK: Boss cheat source (internal & optional)
    
    private static var cheatAnswerProvider: (() -> String?)?
    public static func installCheatAnswerProvider(_ provider: @escaping () -> String?) {
        cheatAnswerProvider = provider
    }
    private func resolveCheatAnswer(lang: Language) -> String? {
        if let p = Self.cheatAnswerProvider, let s = p(), s.count == 5 { return s }
        let ud = UserDefaults.standard
        if let s1 = ud.string(forKey: "WordZap.HiddenAnswer.\(lang.rawValue)"),
           s1.count == 5 { return s1 }
        if let s2 = ud.string(forKey: "WordZap.HiddenAnswer"),
           s2.count == 5 { return s2 }
        return nil
    }
    
    // MARK: Boss memory (presence + green positions)
    
    private var bossKnownLetters: [Language:[Character:Int]] = [:]
    private var bossKnownGreens:  [Language:[Int:Character]] = [:]
    
    // MARK: Factory
    
    fileprivate static func make() throws -> WordleAI {
        let pURL = WordleAI.findOptionalModelURL(named: "WordleGPT_prefill")
        let dURL = WordleAI.findOptionalModelURL(named: "WordleGPT_decode")
        let anyURL = pURL ?? dURL
        guard let anchor = anyURL else {
            let tokURL = try WordleAI.findTokenizerJSON(near: nil)
            let tokenizer = try BPETokenizer(tokenizerJSON: tokURL)
            let T0 = 84
            let spec = Spec(maxT: T0, numL: 16, vocab: tokenizer.vocabSize,
                            padId: tokenizer.bos() ?? 0, eosId: tokenizer.eos() ?? 2)
            let ids   = try MLMultiArray(shape: [1, NSNumber(value: T0)], dataType: .int32)
            let mask  = try MLMultiArray(shape: [1, NSNumber(value: T0)], dataType: .int32)
            let tok11 = try MLMultiArray(shape: [1, 1], dataType: .int32)
            let (mapEN, candEN) = WordleAI.buildLetterMap(tokenizer: tokenizer, pattern: "^[ ]?[a-z]$")
            let (mapHE, candHE) = WordleAI.buildLetterMap(tokenizer: tokenizer, pattern: "^[ ]?[אבגדהוזחטיכלמנסעפצקרשתךםןףץ]$")
            let idsEN = WordleAI.buildWordTokenIDs(tokenizer: tokenizer, lang: .en, length: 5)
            let idsHE = WordleAI.buildWordTokenIDs(tokenizer: tokenizer, lang: .he, length: 5)
            let setEN = Set(idsEN.map { WordleAI.decodeWord($0, with: tokenizer) }.filter { $0.count == 5 })
            let setHE = Set(idsHE.map { WordleAI.decodeWord($0, with: tokenizer) }.filter { $0.count == 5 })
            Self.markAsInitializedFromOtherSource()
            return WordleAI(tokenizer: tokenizer, prefill: nil, decode: nil, fallback: nil,
                            spec: spec, idsMA: ids, maskMA: mask, tok1x1: tok11,
                            letterMapEN: mapEN, candidateEN: candEN,
                            letterMapHE: mapHE, candidateHE: candHE,
                            wordStringSetEN: setEN, wordStringSetHE: setHE,
                            T_prefill: nil, T_decode: nil, T_fallback: nil)
        }
        
        let tokURL = try WordleAI.findTokenizerJSON(near: anchor)
        let tokenizer = try BPETokenizer(tokenizerJSON: tokURL)
        
        func loadModel(_ url: URL?) -> MLModel? {
            guard let url else { return nil }
            if #available(iOS 16.0, *) {
                let cfgs: [MLModelConfiguration] = {
                    let c1 = MLModelConfiguration()
#if targetEnvironment(simulator)
                    c1.computeUnits = .cpuOnly
#else
                    c1.computeUnits = .cpuAndNeuralEngine
#endif
                    let c2 = MLModelConfiguration(); c2.computeUnits = .cpuAndGPU
                    let c3 = MLModelConfiguration(); c3.computeUnits = .cpuOnly
                    return [c1, c2, c3]
                }()
                for c in cfgs {
                    if let m = try? MLModel(contentsOf: url, configuration: c) { return m }
                }
                return try? MLModel(contentsOf: url)
            } else {
                return try? MLModel(contentsOf: url)
            }
        }
        
        let pre = loadModel(pURL)
        let dec = loadModel(dURL)
        let fb  = pre ?? dec
        
        func readT(_ m: MLModel?, id: String, alt: String) -> Int? {
            guard let m else { return nil }
            if let s = m.modelDescription.inputDescriptionsByName[id]?.multiArrayConstraint?.shape,
               let t = s.last?.intValue { return t }
            if let s = m.modelDescription.inputDescriptionsByName[alt]?.multiArrayConstraint?.shape,
               let t = s.last?.intValue { return t }
            return nil
        }
        let tPre = readT(pre, id: "attention_mask", alt: "input_ids")
        let tDec = readT(dec, id: "attention_mask", alt: "input_ids")
        let tFb  = readT(fb,  id: "input_ids",      alt: "attention_mask")
        
        let T0 = tPre ?? tDec ?? tFb ?? 84
        let spec = Spec(maxT: T0, numL: 16, vocab: tokenizer.vocabSize,
                        padId: tokenizer.bos() ?? 0, eosId: tokenizer.eos() ?? 2)
        
        let ids   = try MLMultiArray(shape: [1, NSNumber(value: T0)], dataType: .int32)
        let mask  = try MLMultiArray(shape: [1, NSNumber(value: T0)], dataType: .int32)
        let tok11 = try MLMultiArray(shape: [1, 1], dataType: .int32)
        
        let (mapEN, candEN) = WordleAI.buildLetterMap(tokenizer: tokenizer, pattern: "^[ ]?[a-z]$")
        let (mapHE, candHE) = WordleAI.buildLetterMap(tokenizer: tokenizer, pattern: "^[ ]?[אבגדהוזחטיכלמנסעפצקרשתךםןףץ]$")
        
        let idsEN = WordleAI.buildWordTokenIDs(tokenizer: tokenizer, lang: .en, length: 5)
        let idsHE = WordleAI.buildWordTokenIDs(tokenizer: tokenizer, lang: .he, length: 5)
        let setEN = Set(idsEN.map { WordleAI.decodeWord($0, with: tokenizer) }.filter { $0.count == 5 })
        let setHE = Set(idsHE.map { WordleAI.decodeWord($0, with: tokenizer) }.filter { $0.count == 5 })
        
        Self.markAsInitializedFromOtherSource()
        return WordleAI(tokenizer: tokenizer, prefill: pre, decode: dec, fallback: fb,
                        spec: spec, idsMA: ids, maskMA: mask, tok1x1: tok11,
                        letterMapEN: mapEN, candidateEN: candEN,
                        letterMapHE: mapHE, candidateHE: candHE,
                        wordStringSetEN: setEN, wordStringSetHE: setHE,
                        T_prefill: tPre, T_decode: tDec, T_fallback: tFb)
    }
    
    private init(tokenizer: BPETokenizer, prefill: MLModel?, decode: MLModel?, fallback: MLModel?,
                 spec: Spec, idsMA: MLMultiArray, maskMA: MLMultiArray, tok1x1: MLMultiArray,
                 letterMapEN: [Int: Character], candidateEN: [Int],
                 letterMapHE: [Int: Character], candidateHE: [Int],
                 wordStringSetEN: Set<String>, wordStringSetHE: Set<String>,
                 T_prefill: Int?, T_decode: Int?, T_fallback: Int?) {
        self.tokenizer = tokenizer; self.prefill = prefill; self.decode = decode; self.fallbackModel = fallback
        self.spec = spec; self.idsMA = idsMA; self.maskMA = maskMA; self.tok1x1 = tok1x1
        self.letterMapEN = letterMapEN; self.candidateEN = candidateEN
        self.letterMapHE = letterMapHE; self.candidateHE = candidateHE
        self.wordStringSetEN = wordStringSetEN; self.wordStringSetHE = wordStringSetHE
        self.T_prefill = T_prefill; self.T_decode = T_decode; self.T_fallback = T_fallback
        if let tPre = T_prefill, let tDec = T_decode, tPre != tDec {
            Trace.log("⚠️", "Prefill T=\(tPre) but Decode T=\(tDec). I’ll resize per call.", Fancy.yellow)
        }
    }
    
    // MARK: Public entry points
    
    public func guessNext(history: [GuessHistory], lang: Language, difficulty: AIDifficulty) throws -> String {
        let turnIndex = history.count
        
        // 0) If the last feedback is all green, the answer is literally the last guess.
        if let last = history.last {
            let marks = normalizeFeedback(feedback: last.feedback, count: 5)
            if marks.allSatisfy({ $0 == .green }) {
                let solved = last.word.lowercased()
                Trace.log("✅", "Solved in history → \(solved)", Fancy.green)
                return solved
            }
        }
        
        // 1) Obvious answer?
        if !history.isEmpty {
            var c = MaskedConstraints(lang: lang, length: 5)
            c.reset(wordLength: 5, lang: lang)
            c.ingest(history: history, lang: lang)
            if let forced = obviousAnswerIfAny(constraints: c, lang: lang) {
                Trace.log("✅", "Obvious answer from constraints → \(forced)", Fancy.green)
                return forced
            }
        }
        
        // 2) Boss uses fully constrained path
        if difficulty == .boss {
            let cheatAnswer = resolveCheatAnswer(lang: lang)
            if prefill != nil && decode != nil {
                return try guessWithKV(history: history, lang: lang, difficulty: difficulty,
                                       cheatAnswer: cheatAnswer, turnIndex: turnIndex)
            }
            if prefill == nil, decode != nil, let service = try? LLMService() {
                return try guessWithService(svc: service, history: history, lang: lang, difficulty: difficulty,
                                            cheatAnswer: cheatAnswer, turnIndex: turnIndex)
            }
            if fallbackModel != nil {
                return try guessWithFallback(history: history, lang: lang, difficulty: difficulty,
                                             cheatAnswer: cheatAnswer, turnIndex: turnIndex)
            }
        }
        
        // 3) Non-boss opener
        if history.isEmpty {
            var opener = try pickFirstGuessFromModel(lang: lang)
            opener = maybeMutateFirstGuess(opener, lang: lang, probability: 0.15, maxChanges: 2)
            Trace.log("🎯", "opener → \(opener)", Fancy.cyan)
            return opener
        }
        
        // 4) Normal paths
        if prefill != nil && decode != nil {
            Trace.log("⚡️", "KV path", Fancy.blue)
            return try guessWithKV(history: history, lang: lang, difficulty: difficulty,
                                   cheatAnswer: nil, turnIndex: turnIndex)
        }
        if prefill == nil, decode != nil, let service = try? LLMService() {
            Trace.log("🤖", "Decoder-only via LLMService", Fancy.blue)
            return try guessWithService(svc: service, history: history, lang: lang, difficulty: difficulty,
                                        cheatAnswer: nil, turnIndex: turnIndex)
        }
        if fallbackModel != nil {
            Trace.log("🛟", "Fallback path", Fancy.yellow)
            return try guessWithFallback(history: history, lang: lang, difficulty: difficulty,
                                         cheatAnswer: nil, turnIndex: turnIndex)
        }
        throw NSError(domain: "WordleAI", code: -100, userInfo: [NSLocalizedDescriptionKey: "No Core ML model loaded"])
    }
    
    public func pickFirstGuessFromModel(lang: Language) throws -> String {
        var pool = Self.buildWordTokenIDs(tokenizer: tokenizer, lang: lang, length: 5)
        
        let logitsRaw: [Float]
        if prefill != nil {
            let (lg, _, _, _) = try prefillOnce(prompt: (lang == .en ? "<|en|>\n" : "<|he|>\n"))
            logitsRaw = lg
        } else if let fb = fallbackModel {
            let prompt = (lang == .en ? "<|en|>\n" : "<|he|>\n")
            let ids = encodePromptFallback(prompt)
            logitsRaw = try predictLogitsFallback(inputIds: ids, model: fb)
        } else { return lang == .en ? "adieu" : "מגניב" }
        
        let vocabCap = logitsRaw.count
        pool.removeAll(where: { $0 < 0 || $0 >= vocabCap })
        guard !pool.isEmpty else { return lang == .en ? "rocky" : "שלומך" }
        
        let ud  = UserDefaults.standard
        let key = "WordleAI.OpenerTokenRecent.v3.\(lang.rawValue)"
        var recent = (ud.array(forKey: key) as? [Int] ?? []).filter { pool.contains($0) }
        let cooldown = Self.cooldownSize(poolCount: pool.count)
        if recent.count > cooldown { recent.removeFirst(recent.count - cooldown) }
        var eligible = pool.filter { !recent.contains($0) }
        if eligible.count < max(16, pool.count / 50) {
            let drop = max(1, recent.count / 4); if drop > 0 { recent.removeFirst(min(drop, recent.count)) }
            eligible = pool.filter { !recent.contains($0) }
        }
        if eligible.isEmpty { eligible = pool }
        
        var adjusted = logitsRaw
        for tid in eligible where tid < adjusted.count {
            let w = Self.decodeWord(tid, with: tokenizer)
            if w.count == 5 { adjusted[tid] = logitsRaw[tid] + openerBias(for: w, lang: lang) }
        }
        
        var word = ""
        for _ in 0..<12 {
            let id = sampleRestricted(logits: adjusted, candidates: eligible,
                                      temperature: 0.85, topK: max(300, min(eligible.count, 1024)))
            if id >= 0 && id < adjusted.count {
                let w = Self.decodeWord(id, with: tokenizer)
                if w.count == 5, isGoodFirstOpener(w, lang: lang), !isMonotonicSequence(w, lang: lang) {
                    word = w; recent.append(id); break
                }
            }
        }
        if word.isEmpty {
            if let id = eligible.first(where: {
                let w = Self.decodeWord($0, with: tokenizer)
                return w.count == 5 && isGoodFirstOpener(w, lang: lang) && !isMonotonicSequence(w, lang: lang)
            }) { word = Self.decodeWord(id, with: tokenizer); recent.append(id) }
        }
        if word.isEmpty { word = lang == .en ? "house" : "מגניב" }
        if recent.count > cooldown { recent.removeFirst(recent.count - cooldown) }
        ud.set(Array(NSOrderedSet(array: recent)) as! [Int], forKey: key)
        Trace.log("ℹ️", "First Word = \(word)", Fancy.blue)
        return word
    }
    
    public func warmUp() {
        if prefill != nil { _ = try? prefillOnce(prompt: "<|en|>\n") }
        else if fallbackModel != nil {
            let T = T_fallback ?? spec.maxT
            let ids = Array(repeating: tokenizer.bos() ?? 0, count: T)
            _ = try? predictLogitsFallback(inputIds: ids, model: fallbackModel!)
        }
        
        warmedUp = true
    }
    
    // MARK: Opener quality & bias
    
    private func openerBias(for w: String, lang: Language) -> Float {
        let s = w.lowercased(); guard s.count == 5 else { return 0 }
        let chars = Array(s)
        var counts: [Character:Int] = [:]
        for c in chars { counts[c, default: 0] += 1 }
        let maxDup = counts.values.max() ?? 1
        let distinct = counts.count
        
        var dupPenalty: Float = 0
        if maxDup >= 3 { dupPenalty -= 10 }
        if counts.values.filter({ $0 == 2 }).count >= 2 { dupPenalty -= 2.0 }
        if lang == .en { for h in "qjxz" where (counts[h] ?? 0) >= 2 { dupPenalty -= 6.0 } }
        
        var H: Float = 0
        for c in counts.values {
            let p = Float(c) / 5.0
            H += -p * log2f(p)
        }
        let entropyBoost: Float = (H / 2.32) * 2.0
        
        let vowelsEN = Set("aeiouy")
        let vowelsHE: Set<Character> = ["א","ה","ו","י"]
        let V = (lang == .en ? vowelsEN : vowelsHE)
        let vowelCount = chars.reduce(0) { $0 + (V.contains($1) ? 1 : 0) }
        let vowelNudge: Float = (vowelCount >= 2 ? 0.7 : (vowelCount == 1 ? -0.4 : -0.8))
        
        let freq = unigramFreq(lang: lang)
        var coverage: Float = 0
        for c in Set(chars) {
            let f = Float(freq[c] ?? 0.0005); coverage += min(f * 4.0, 1.2)
        }
        
        var bigrams = Set<String>()
        for i in 1..<chars.count { bigrams.insert(String([chars[i-1], chars[i]])) }
        let bigramBoost: Float = Float(bigrams.count) * 0.15
        
        let distinctBoost: Float = Float(distinct - 3) * 0.3
        
        return entropyBoost + vowelNudge + coverage + bigramBoost + distinctBoost + dupPenalty
    }
    
    private func isGoodFirstOpener(_ w: String, lang: Language) -> Bool {
        let s = w.lowercased()
        guard s.count == 5 else { return false }
        var counts: [Character:Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        
        if counts.values.contains(where: { $0 >= 3 }) { return false }
        if counts.values.filter({ $0 == 2 }).count > 1 { return false }
        if counts.count < 4 { return false }
        
        if shannonEntropy(s) < openerMinEntropy { return false }
        
        if lang == .en {
            for h in "qjxz" { if (counts[h] ?? 0) >= 2 { return false } }
        }
        return true
    }
    
    private func unigramFreq(lang: Language) -> [Character: Double] {
        if lang == .en {
            return [
                "e":0.127,"t":0.091,"a":0.082,"o":0.075,"i":0.070,"n":0.067,"s":0.063,"h":0.061,"r":0.060,
                "d":0.043,"l":0.040,"c":0.028,"u":0.028,"m":0.024,"w":0.024,"f":0.022,"g":0.020,"y":0.020,
                "p":0.019,"b":0.015,"v":0.010,"k":0.008,"j":0.002,"x":0.002,"q":0.001,"z":0.001
            ]
        } else {
            let pairs: [(Character, Double)] = [
                ("א",0.10),("ה",0.09),("י",0.09),("ו",0.08),("ל",0.07),
                ("מ",0.07),("ר",0.06),("נ",0.06),("ת",0.06),("ש",0.05),
                ("ק",0.04),("ד",0.03),("ח",0.03),("כ",0.03),("ע",0.03),
                ("ב",0.03),("פ",0.02),("ס",0.02),("צ",0.01),("ג",0.01),
                ("ט",0.01),("ז",0.01),("ך",0.005),("ם",0.005),("ן",0.005),("ף",0.005),("ץ",0.005)
            ]
            var map: [Character:Double] = [:]; for (c,f) in pairs { map[c] = f }; return map
        }
    }
}

// MARK: - Helpers (opener + misc)

private extension WordleAI {
    static func decodeWord(_ tokenId: Int, with tok: BPETokenizer) -> String {
        var s = tok.decode([tokenId]).lowercased()
        if s.first == " " { s.removeFirst() }
        return s
    }
    
    static func buildWordTokenIDs(tokenizer: BPETokenizer, lang: Language, length: Int) -> [Int] {
        var ids: [Int] = []
        let allowedEN = Set("abcdefghijklmnopqrstuvwxyz")
        let allowedHE = Set("אבגדהוזחטיכלמנסעפצקרשתךםןףץ")
        let allowed = (lang == .en) ? allowedEN : allowedHE
        for id in 0..<tokenizer.vocabSize {
            let raw = tokenizer.decode([id])
            guard !raw.isEmpty, raw.first != " " else { continue }
            let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard lower.count == length, lower.allSatisfy({ allowed.contains($0) }) else { continue }
            ids.append(id)
        }
        return ids
    }
    
    static func buildLetterMap(tokenizer: BPETokenizer, pattern: String) -> ([Int: Character], [Int]) {
        let rx = try! NSRegularExpression(pattern: pattern, options: [])
        var map: [Int: Character] = [:]; var ids: [Int] = []
        for id in 0..<tokenizer.vocabSize {
            let s = tokenizer.decode([id])
            if rx.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil,
               let ch = s.last {
                map[id] = ch; ids.append(id)
            }
        }
        return (map, ids)
    }
    
    private func isMonotonicSequence(_ w: String, lang: Language) -> Bool {
        let s = Array(w.unicodeScalars); guard s.count >= 4 else { return false }
        var up = 0, down = 0
        for i in 1..<s.count {
            let d = Int(s[i].value) - Int(s[i-1].value)
            if d == 1 { up += 1 } else if d == -1 { down += 1 }
        }
        return up >= s.count - 1 || down >= s.count - 1
    }
    
    private static func cooldownSize(poolCount n: Int) -> Int { max(64, min(512, Int(Double(n) * 0.05))) }
    
    func shannonEntropy(_ w: String) -> Double {
        guard !w.isEmpty else { return 0 }
        var counts: [Character:Int] = [:]
        for c in w { counts[c, default: 0] += 1 }
        let n = Double(w.count)
        var H = 0.0
        for (_, c) in counts { let p = Double(c) / n; H += -p * log2(p) }
        return H
    }
    
    func maybeMutateFirstGuess(_ word: String, lang: Language,
                               probability: Double = 0.15, maxChanges: Int = 2) -> String {
        guard Double.random(in: 0..<1) < probability else { return word }
        let pool = (lang == .en) ? wordStringSetEN : wordStringSetHE
        guard !pool.isEmpty, word.count == 5 else { return word }
        
        let alpha: [Character] = (lang == .en)
        ? Array("abcdefghijklmnopqrstuvwxyz")
        : Array("אבגדהוזחטיכלמנסעפצקרשת")
        
        let base = word.lowercased()
        let baseScore = openerBias(for: base, lang: lang)
        
        for _ in 0..<32 {
            var c = Array(base)
            for i in Array(0..<c.count).shuffled().prefix(Int.random(in: 1...maxChanges)) {
                c[i] = alpha.randomElement()!
            }
            let m = String(c)
            
            if m != base,
               pool.contains(m),
               isGoodFirstOpener(m, lang: lang),
               !isMonotonicSequence(m, lang: lang) {
                
                let score = openerBias(for: m, lang: lang)
                if score > baseScore {
                    Trace.log("🎲", "mutated \(base) → \(m) (Δ=\(String(format: "%.2f", score - baseScore)))", Fancy.mag)
                    return m
                }
            }
        }
        return word
    }
    
    // MARK: Obvious-answer fast path
    func obviousAnswerIfAny(constraints: MaskedConstraints, lang: Language) -> String? {
        let pool = (lang == .en) ? wordStringSetEN : wordStringSetHE
        guard !pool.isEmpty else { return nil }
        var candidate: String? = nil
        var seen = 0
        for w in pool {
            if satisfies(word: w, constraints: constraints) {
                seen += 1
                if seen == 1 { candidate = w }
                if seen > 1 { return nil }
            }
        }
        return candidate
    }
    
    func satisfies(word: String, constraints: MaskedConstraints) -> Bool {
        let w = word.lowercased()
        guard w.count == constraints.length else { return false }
        let chars = Array(w)
        
        for i in 0..<constraints.length {
            let ch = chars[i]
            if let fx = constraints.fixed[i], ch != fx { return false }
            if constraints.bannedAt[i].contains(ch) { return false }
        }
        
        for ch in constraints.disallow where w.contains(ch) { return false }
        
        var counts: [Character:Int] = [:]; for ch in chars { counts[ch, default: 0] += 1 }
        for (ch, need) in constraints.minCount {
            if counts[ch, default: 0] < need { return false }
        }
        for (ch, mx) in constraints.maxCount {
            if counts[ch, default: 0] > mx { return false }
        }
        return true
    }
}

// MARK: - Boss discovery model

private struct BossPresencePlan {
    var need: [Character:Int] = [:]
}

private extension WordleAI {
    func updateBossMemoryForTurn(lang: Language,
                                 solution: String,
                                 turnIndex: Int,
                                 constraints: inout MaskedConstraints) -> BossPresencePlan {
        guard solution.count == 5 else { return BossPresencePlan() }
        if turnIndex == 0 {
            bossKnownLetters[lang] = [:]
            bossKnownGreens[lang]  = [:]
        }
        
        var knownP = bossKnownLetters[lang] ?? [:]
        var knownG = bossKnownGreens[lang]  ?? [:]
        
        let sArr = Array(solution.lowercased())
        var solCount: [Character:Int] = [:]; for c in sArr { solCount[c, default: 0] += 1 }
        
        var greensFromHistory: [Character:Int] = [:]
        for fx in constraints.fixed { if let ch = fx { greensFromHistory[ch, default: 0] += 1 } }
        
        for (pos, ch) in knownG { constraints.fixed[pos] = ch }
        for (ch, lim) in solCount { constraints.maxCount[ch] = min(constraints.maxCount[ch] ?? Int.max, lim) }
        
        let baseMin = constraints.minCount
        
        func greensKnownFromMemory(_ ch: Character) -> Int {
            knownG.values.reduce(0) { $0 + ($1 == ch ? 1 : 0) }
        }
        func totalGreens(_ ch: Character) -> Int {
            greensFromHistory[ch, default: 0] + greensKnownFromMemory(ch)
        }
        func assuredCount(_ ch: Character) -> Int {
            max(constraints.minCount[ch] ?? 0, totalGreens(ch))
        }
        func residualCount(_ ch: Character) -> Int {
            max(0, (solCount[ch] ?? 0) - assuredCount(ch))
        }
        
        @discardableResult
        func attemptPresence() -> Character? {
            var pool: [Character] = []
            for (ch, _) in solCount {
                let res = residualCount(ch)
                if res > 0 {
                    let hinted = (constraints.minCount[ch, default: 0] > totalGreens(ch)) ? 2 : 1
                    for _ in 0..<(res * hinted) { pool.append(ch) }
                }
            }
            guard !pool.isEmpty else { return nil }
            let pick = pool.randomElement()!
            knownP[pick, default: 0] += 1
            let seen = knownP[pick] ?? 1
            constraints.minCount[pick] = max(constraints.minCount[pick] ?? 0, seen)
            Trace.log("🧠", "Boss learned presence \(pick)", Fancy.cyan)
            return pick
        }
        
        @discardableResult
        func attemptPosition() -> Int? {
            var positions: [Int] = []
            for i in 0..<sArr.count where constraints.fixed[i] == nil && knownG[i] == nil {
                let ch = sArr[i]
                if totalGreens(ch) < (solCount[ch] ?? 0) { positions.append(i) }
            }
            guard !positions.isEmpty else { return nil }
            func desirability(_ i: Int) -> Int {
                let L = sArr[i]
                let hinted = (constraints.minCount[L, default: 0] > totalGreens(L)) ? 1 : 0
                let learned = (knownP[L] ?? 0) > 0 ? 1 : 0
                return hinted * 2 + learned
            }
            positions.sort { desirability($0) > desirability($1) }
            let pickPos = positions.first!
            let ch = sArr[pickPos]
            knownG[pickPos] = ch
            constraints.fixed[pickPos] = ch
            Trace.log("🧠", "Boss locked green @\(pickPos)=\(ch)", Fancy.cyan)
            return pickPos
        }
        
        let presenceRoll = (Double.random(in: 0..<1) < 0.50)
        let extraChance  = (turnIndex >= 2) ? 0.30 : 0.10
        let extraRoll    = (Double.random(in: 0..<1) < extraChance)
        
        if presenceRoll { _ = attemptPresence() }
        if extraRoll {
            let goPositionFirst = (Double.random(in: 0..<1) < 0.5)
            if goPositionFirst {
                if attemptPosition() == nil { _ = attemptPresence() }
            } else {
                if attemptPresence() == nil { _ = attemptPosition() }
            }
        }
        
        bossKnownLetters[lang] = knownP
        bossKnownGreens[lang]  = knownG
        
        var need: [Character:Int] = [:]
        for (ch, lim) in solCount { constraints.maxCount[ch] = min(constraints.maxCount[ch] ?? Int.max, lim) }
        for (ch, now) in constraints.minCount {
            let before = baseMin[ch] ?? 0
            if now > before { need[ch] = now - before }
        }
        return BossPresencePlan(need: need)
    }
}

// MARK: - KV path

private extension WordleAI {
    func ensureBuffers(T: Int) {
        let curT1 = idsMA.shape.last?.intValue ?? -1
        if curT1 != T { idsMA = try! MLMultiArray(shape: [1, NSNumber(value: T)], dataType: .int32) }
        let curT2 = maskMA.shape.last?.intValue ?? -1
        if curT2 != T { maskMA = try! MLMultiArray(shape: [1, NSNumber(value: T)], dataType: .int32) }
    }
    
    func alignKVsForDecode(ks: [MLMultiArray], vs: [MLMultiArray]) -> ([MLMultiArray], [MLMultiArray], Int) {
        guard let first = ks.first ?? vs.first else { return (ks, vs, 0) }
        let shape = first.shape.map(\.intValue)
        guard shape.count == 4 else { return (ks, vs, shape.count >= 3 ? shape[2] : 0) }
        let curT = shape[2]
        let decT = T_decode ?? spec.maxT
        let targetT = max(0, min(curT, max(0, decT - 1)))
        guard targetT != curT else { return (ks, vs, curT) }
        func sliceRight(_ ma: MLMultiArray, to target: Int) -> MLMultiArray {
            let H = ma.shape[1].intValue, W = ma.shape[2].intValue, D = ma.shape[3].intValue
            let out = try! MLMultiArray(shape: [1, NSNumber(value: H), NSNumber(value: target), NSNumber(value: D)], dataType: ma.dataType)
            let ps = ma.strides.map { $0.intValue }; let qs = out.strides.map { $0.intValue }
            let start = max(0, W - target)
            for h in 0..<H { for t in 0..<target { for d in 0..<D {
                out[0*qs[0] + h*qs[1] + t*qs[2] + d*qs[3]] =
                ma [0*ps[0] + h*ps[1] + (start + t)*ps[2] + d*ps[3]]
            }}}
            return out
        }
        let ksT = ks.map { sliceRight($0, to: targetT) }
        let vsT = vs.map { sliceRight($0, to: targetT) }
        return (ksT, vsT, targetT)
    }
    
    func guessWithKV(history: [GuessHistory], lang: Language, difficulty: AIDifficulty,
                     cheatAnswer: String?, turnIndex: Int) throws -> String
    {
        let prompt = buildPrompt(history: history, lang: lang)
        let (logits0, k0, v0, usedLen) = try prefillOnce(prompt: prompt)
        
        let (kAligned, vAligned, alignedLen) = alignKVsForDecode(ks: k0, vs: v0)
        pastK = kAligned; pastV = vAligned
        curLen = min(usedLen, alignedLen)
        Trace.log("ℹ️", "KV layers K=\(pastK.count) V=\(pastV.count)")
        
        var constraints = MaskedConstraints(lang: lang, length: 5)
        constraints.reset(wordLength: 5, lang: lang)
        constraints.ingest(history: history, lang: lang)
        
        if let forced = obviousAnswerIfAny(constraints: constraints, lang: lang) {
            Trace.log("✅", "Obvious answer from constraints → \(forced)", Fancy.green)
            return forced
        }
        
        if difficulty == .boss, let ans = cheatAnswer {
            _ = updateBossMemoryForTurn(lang: lang, solution: ans, turnIndex: turnIndex, constraints: &constraints)
        }
        
        let (temp, topK) = difficulty.params
        let id2c = filteredId2c((lang == .en) ? letterMapEN : letterMapHE, vocab: logits0.count)
        let inv  = invert(id2c)
        let clean = ((lang == .en) ? candidateEN : candidateHE)
            .filter { $0 >= 0 && $0 < logits0.count && !tokenStartsWithSpace(tokenId: $0) }
        
        var result: [Character] = []
        var used: [Character: Int] = [:]
        var logits = logits0
        
        for pos in 0..<5 {
            var masked = logits
            for tid in 0..<masked.count where !clean.contains(tid) { masked[tid] = -1e30 }
            constraints.apply(at: pos, used: used, id2c: id2c, logits: &masked, negInf: -1e30)
            applySoftRepeatPenalty(at: pos, used: used, result: result, constraints: constraints, id2c: id2c, logits: &masked)
            forceDeficitIfNeeded(at: pos, constraints: constraints, used: used, invMap: inv, logits: &masked)
            avoidExtraCopiesWhileDeficit(at: pos, constraints: constraints, used: used, id2c: id2c, logits: &masked)
            maskDuplicatesUnlessRequired(at: pos, constraints: constraints, used: used, id2c: id2c, logits: &masked)
            
            var nextId = sampleRestricted(logits: masked, candidates: clean, temperature: temp, topK: topK)
            var ch = id2c[nextId]
            if ch == nil || !isAllowed(ch!, at: pos, used: used, constraints: constraints) {
                let fb = pickFallbackChar(position: pos, used: used, constraints: constraints, lang: lang)
                ch = fb; if let forced = inv[fb]?.first { nextId = forced }
            }
            if let c = ch { result.append(c); used[c, default: 0] += 1 }
            do { logits = try decodeOnce(nextId: nextId) }
            catch {
                Trace.log("🛟", "Decode failed @\(pos) — sliding fallback", Fancy.yellow)
                return try guessWithFallback(history: history, lang: lang, difficulty: difficulty,
                                             cheatAnswer: cheatAnswer, turnIndex: turnIndex)
            }
        }
        let out = String(result)
        Trace.log("⚡️", "guess → \(out)", Fancy.blue)
        return out
    }
    
    func guessWithService(svc: LLMService, history: [GuessHistory], lang: Language, difficulty: AIDifficulty,
                          cheatAnswer: String?, turnIndex: Int) throws -> String
    {
        var constraints = MaskedConstraints(lang: lang, length: 5)
        constraints.reset(wordLength: 5, lang: lang)
        constraints.ingest(history: history, lang: lang)
        
        if let forced = obviousAnswerIfAny(constraints: constraints, lang: lang) {
            Trace.log("✅", "Obvious answer from constraints → \(forced)", Fancy.green)
            return forced
        }
        
        if difficulty == .boss, let ans = cheatAnswer {
            _ = updateBossMemoryForTurn(lang: lang, solution: ans, turnIndex: turnIndex, constraints: &constraints)
        }
        
        let prompt = buildPrompt(history: history, lang: lang)
        let ids = tokenizer.encode(prompt, addBOS: true)
        try svc.resetSequence()
        var logits: [Float] = []
        for id in ids { logits = try svc.step(tokenId: Int32(id), expectedVocab: spec.vocab) }
        
        let (temp, topK) = difficulty.params
        let id2c = filteredId2c((lang == .en) ? letterMapEN : letterMapHE, vocab: logits.count)
        let inv  = invert(id2c)
        let clean = ((lang == .en) ? candidateEN : candidateHE)
            .filter { $0 >= 0 && $0 < logits.count && !tokenStartsWithSpace(tokenId: $0) }
        
        var result: [Character] = []
        var used: [Character:Int] = [:]
        
        for pos in 0..<5 {
            var masked = logits
            for tid in 0..<masked.count where !clean.contains(tid) { masked[tid] = -1e30 }
            constraints.apply(at: pos, used: used, id2c: id2c, logits: &masked, negInf: -1e30)
            applySoftRepeatPenalty(at: pos, used: used, result: result, constraints: constraints, id2c: id2c, logits: &masked)
            forceDeficitIfNeeded(at: pos, constraints: constraints, used: used, invMap: inv, logits: &masked)
            avoidExtraCopiesWhileDeficit(at: pos, constraints: constraints, used: used, id2c: id2c, logits: &masked)
            maskDuplicatesUnlessRequired(at: pos, constraints: constraints, used: used, id2c: id2c, logits: &masked)
            
            var nextId = sampleRestricted(logits: masked, candidates: clean, temperature: temp, topK: topK)
            var ch = id2c[nextId]
            if ch == nil || !isAllowed(ch!, at: pos, used: used, constraints: constraints) {
                let fb = pickFallbackChar(position: pos, used: used, constraints: constraints, lang: lang)
                ch = fb; if let forced = inv[fb]?.first { nextId = forced }
            }
            if let c = ch { result.append(c); used[c, default: 0] += 1 }
            logits = try svc.step(tokenId: Int32(nextId), expectedVocab: spec.vocab)
        }
        let out = String(result)
        Trace.log("🤖", "decoder-only service guess → \(out)", Fancy.blue)
        return out
    }
    
    func prefillOnce(prompt: String) throws -> ([Float], [MLMultiArray], [MLMultiArray], Int) {
        guard let prefill else {
            throw NSError(domain: "WordleAI", code: -200, userInfo: [NSLocalizedDescriptionKey: "Prefill not loaded"])
        }
        let T = T_prefill ?? spec.maxT
        ensureBuffers(T: T)
        var ids = tokenizer.encode(prompt, addBOS: true)
        if ids.count > T { ids = Array(ids.suffix(T)) }
        let real = ids.count
        if real < T { ids = Array(repeating: spec.padId, count: T - real) + ids }
        let ip = idsMA.dataPointer.bindMemory(to: Int32.self, capacity: idsMA.count)
        let mp = maskMA.dataPointer.bindMemory(to: Int32.self, capacity: maskMA.count)
        for i in 0..<T { ip[i] = Int32(ids[i]); mp[i] = (i < (T - real)) ? 0 : 1 }
        let out = try prefill.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "input_ids": idsMA, "attention_mask": maskMA
        ]))
        guard let (logits, ks, vs) = Self.extractKVOutputs(from: out, vocab: spec.vocab, L: spec.numL)
        else { throw NSError(domain: "WordleAI", code: -201, userInfo: [NSLocalizedDescriptionKey: "Bad prefill outputs"]) }
        Trace.log("ℹ️", "KV layers K=\(ks.count) V=\(vs.count)")
        return (logits, ks, vs, real)
    }
    
    func decodeOnce(nextId: Int) throws -> [Float] {
        guard let decode else {
            throw NSError(domain: "WordleAI", code: -210, userInfo: [NSLocalizedDescriptionKey: "Decode not loaded"])
        }
        let T = T_decode ?? T_prefill ?? spec.maxT
        ensureBuffers(T: T)
        curLen = min(curLen + 1, T)
        let mp = maskMA.dataPointer.bindMemory(to: Int32.self, capacity: maskMA.count)
        for i in 0..<T { mp[i] = (i < (T - curLen)) ? 0 : 1 }
        tok1x1[0] = NSNumber(value: nextId)
        
        var dict: [String: MLFeatureValue] = [
            "input_ids": MLFeatureValue(multiArray: tok1x1),
            "attention_mask": MLFeatureValue(multiArray: maskMA)
        ]
        let (kOK, vOK, _) = alignKVsForDecode(ks: pastK, vs: pastV)
        for i in 0..<kOK.count { dict[String(format: "past_k_%02d", i)] = MLFeatureValue(multiArray: kOK[i]) }
        for i in 0..<vOK.count { dict[String(format: "past_v_%02d", i)] = MLFeatureValue(multiArray: vOK[i]) }
        
        let out = try decode.prediction(from: MLDictionaryFeatureProvider(dictionary: dict))
        guard let (logits, ks, vs) = Self.extractKVOutputs(from: out, vocab: spec.vocab, L: spec.numL)
        else { throw NSError(domain: "WordleAI", code: -211, userInfo: [NSLocalizedDescriptionKey: "Bad decode outputs"]) }
        let (kAligned, vAligned, _) = alignKVsForDecode(ks: ks, vs: vs)
        pastK = kAligned; pastV = vAligned
        return logits
    }
}

// MARK: - Fallback path

private extension WordleAI {
    func guessWithFallback(history: [GuessHistory], lang: Language, difficulty: AIDifficulty,
                           cheatAnswer: String?, turnIndex: Int) throws -> String
    {
        guard let model = fallbackModel else {
            throw NSError(domain: "WordleAI", code: -300, userInfo: [NSLocalizedDescriptionKey: "No fallback model"])
        }
        let prompt = buildPrompt(history: history, lang: lang)
        var ids = encodePromptFallback(prompt)
        
        var constraints = MaskedConstraints(lang: lang, length: 5)
        constraints.reset(wordLength: 5, lang: lang)
        constraints.ingest(history: history, lang: lang)
        
        if let forced = obviousAnswerIfAny(constraints: constraints, lang: lang) {
            Trace.log("✅", "Obvious answer from constraints → \(forced)", Fancy.green)
            return forced
        }
        
        if difficulty == .boss, let ans = cheatAnswer {
            _ = updateBossMemoryForTurn(lang: lang, solution: ans, turnIndex: turnIndex, constraints: &constraints)
        }
        
        let (temp, topK) = difficulty.params
        var logits = try predictLogitsFallback(inputIds: ids, model: model)
        let id2c = filteredId2c((lang == .en) ? letterMapEN : letterMapHE, vocab: logits.count)
        let inv  = invert(id2c)
        let clean = ((lang == .en) ? candidateEN : candidateHE)
            .filter { $0 >= 0 && $0 < logits.count && !tokenStartsWithSpace(tokenId: $0) }
        
        var result: [Character] = []
        var used: [Character:Int] = [:]
        
        for pos in 0..<5 {
            var masked = logits
            for tid in 0..<masked.count where !clean.contains(tid) { masked[tid] = -1e30 }
            constraints.apply(at: pos, used: used, id2c: id2c, logits: &masked, negInf: -1e30)
            applySoftRepeatPenalty(at: pos, used: used, result: result, constraints: constraints, id2c: id2c, logits: &masked)
            forceDeficitIfNeeded(at: pos, constraints: constraints, used: used, invMap: inv, logits: &masked)
            avoidExtraCopiesWhileDeficit(at: pos, constraints: constraints, used: used, id2c: id2c, logits: &masked)
            maskDuplicatesUnlessRequired(at: pos, constraints: constraints, used: used, id2c: id2c, logits: &masked)
            
            var nextId = sampleRestricted(logits: masked, candidates: clean, temperature: temp, topK: topK)
            var ch = id2c[nextId]
            if ch == nil || !isAllowed(ch!, at: pos, used: used, constraints: constraints) {
                Trace.log("🚫", "over-masked @\(pos) → fallback char", Fancy.gray)
                let fb = pickFallbackChar(position: pos, used: used, constraints: constraints, lang: lang)
                ch = fb; if let forced = inv[fb]?.first { nextId = forced }
            }
            if let c = ch { result.append(c); used[c, default: 0] += 1 }
            ids.removeFirst(); ids.append(nextId)
            logits = try predictLogitsFallback(inputIds: ids, model: model)
        }
        let out = String(result)
        Trace.log("🛟", "guess → \(out)", Fancy.yellow)
        return out
    }
    
    func encodePromptFallback(_ text: String) -> [Int] {
        if let cached = encodeCache.get(text) { return cached }
        let T = T_fallback ?? spec.maxT
        var ids = tokenizer.encode(text, addBOS: true)
        if ids.count > T { ids = Array(ids.suffix(T)) }
        if ids.count < T { ids = Array(repeating: tokenizer.bos() ?? 0, count: T - ids.count) + ids }
        encodeCache.set(text, ids); return ids
    }
    
    func predictLogitsFallback(inputIds: [Int], model: MLModel) throws -> [Float] {
        if let cached = logitsCache.get(inputIds) { return cached }
        let T = T_fallback ?? spec.maxT
        ensureBuffers(T: T)
        let ip = idsMA.dataPointer.bindMemory(to: Int32.self, capacity: idsMA.count)
        let mp = maskMA.dataPointer.bindMemory(to: Int32.self, capacity: maskMA.count)
        for i in 0..<T { ip[i] = Int32(inputIds[i]); mp[i] = 1 }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "input_ids": idsMA, "attention_mask": maskMA
        ]))
        let ma = out.featureNames.compactMap { out.featureValue(for: $0)?.multiArrayValue }.first
        guard let logitsMA = ma else { throw NSError(domain: "WordleAI", code: -305, userInfo: [NSLocalizedDescriptionKey: "No logits output"]) }
        var logits = [Float](repeating: 0, count: logitsMA.count)
        for i in 0..<logitsMA.count { logits[i] = logitsMA[i].floatValue }
        logitsCache.set(inputIds, logits); return logits
    }
}

// MARK: - Constraints

private enum FBMark { case green, yellow, gray }

private struct MaskedConstraints {
    let length: Int
    var fixed: [Character?]
    var bannedAt: [Set<Character>]
    var disallow: Set<Character>
    var minCount: [Character: Int]
    var maxCount: [Character: Int]
    
    init(lang: Language, length: Int) {
        self.length = length
        self.fixed = Array(repeating: nil, count: length)
        self.bannedAt = Array(repeating: [], count: length)
        self.disallow = []
        self.minCount = [:]
        self.maxCount = [:]
    }
    mutating func reset(wordLength: Int, lang: Language) {
        fixed = Array(repeating: nil, count: wordLength)
        bannedAt = Array(repeating: [], count: wordLength)
        disallow.removeAll(); minCount.removeAll(); maxCount.removeAll()
    }
    mutating func ingest(history: [GuessHistory], lang: Language) {
        for (w, f) in history { ingestRow(word: w.lowercased(), feedback: f, lang: lang) }
    }
    mutating func ingestRow(word: String, feedback: String, lang: Language) {
        guard word.count == length else { return }
        let ws = Array(word)
        let fs = normalizeFeedback(feedback: feedback, count: length)
        for i in 0..<length {
            let ch = ws[i]
            switch fs[i] {
            case .green: fixed[i] = ch
            case .yellow: bannedAt[i].insert(ch)
            case .gray: bannedAt[i].insert(ch)
            }
        }
        var row: [Character:(k:Int, r:Int)] = [:]
        for i in 0..<length {
            let ch = ws[i]
            var rec = row[ch] ?? (0,0)
            rec.k += 1; if fs[i] != .gray { rec.r += 1 }; row[ch] = rec
        }
        for (ch, v) in row {
            if v.r > 0 { minCount[ch] = max(minCount[ch] ?? 0, v.r) }
            if v.r < v.k { maxCount[ch] = min(maxCount[ch] ?? v.r, v.r) }
            if v.k > 0, v.r == 0 { maxCount[ch] = 0; disallow.insert(ch) }
        }
        Trace.log("🧩", "min:\(minCount) max:\(maxCount)", Fancy.green)
    }
    func apply(at position: Int, used: [Character: Int], id2c: [Int: Character], logits: inout [Float], negInf: Float) {
        if let fx = fixed[position] {
            for (tid, ch) in id2c where tid < logits.count { logits[tid] = (ch == fx) ? logits[tid] : negInf }
            return
        }
        for (tid, ch) in id2c where tid < logits.count {
            if disallow.contains(ch) || bannedAt[position].contains(ch) {
                logits[tid] = negInf; continue
            }
            if let mx = maxCount[ch], used[ch, default: 0] >= mx { logits[tid] = negInf }
        }
    }
}

private func normalizeFeedback(feedback: String, count: Int) -> [FBMark] {
    let f = Array(feedback); var out: [FBMark] = []
    for i in 0..<min(count, f.count) {
        switch f[i] {
        case "🟩","🟢","G","g": out.append(.green)
        case "🟨","Y","y":     out.append(.yellow)
        default:              out.append(.gray)
        }
    }
    while out.count < count { out.append(.gray) }
    return out
}

// MARK: - Masking helpers

private extension WordleAI {
    func applySoftRepeatPenalty(
        at pos: Int,
        used: [Character: Int],
        result: [Character],
        constraints: MaskedConstraints,
        id2c: [Int: Character],
        logits: inout [Float]
    ) {
        var lastRunChar: Character? = nil
        var lastRunLen = 0
        if let last = result.last {
            lastRunChar = last
            lastRunLen = 1
            if result.count >= 2, result[result.count - 2] == last { lastRunLen = 2 }
        }
        for (tid, ch) in id2c where tid < logits.count {
            let usedCount = used[ch, default: 0]
            let requiredMin = constraints.minCount[ch, default: 0]
            let allowUpTo  = max(1, requiredMin)
            if usedCount >= allowUpTo {
                let dupIdx = usedCount - allowUpTo + 1
                logits[tid] -= 0.85 * Float(min(3, dupIdx))
            }
            if let lr = lastRunChar, lr == ch { logits[tid] -= (lastRunLen >= 2) ? 1.75 : 0.90 }
            if "aeiou".contains(ch), used[ch, default: 0] >= 2 { logits[tid] -= 0.6 }
        }
    }
    
    /// While any min-count is unmet, ban extra copies of letters already at their minimum.
    func avoidExtraCopiesWhileDeficit(
        at pos: Int,
        constraints: MaskedConstraints,
        used: [Character:Int],
        id2c: [Int: Character],
        logits: inout [Float]
    ) {
        var deficitExists = false
        for (ch, need) in constraints.minCount {
            if (need - used[ch, default: 0]) > 0 { deficitExists = true; break }
        }
        guard deficitExists else { return }
        for (tid, ch) in id2c where tid < logits.count {
            let minNeeded = constraints.minCount[ch] ?? 0
            if minNeeded > 0, used[ch, default: 0] >= minNeeded {
                logits[tid] = -1e30
            }
        }
    }
    
    func maskDuplicatesUnlessRequired(at pos: Int, constraints: MaskedConstraints, used: [Character:Int],
                                      id2c: [Int: Character], logits: inout [Float]) {
        var remaining = 0
        for (ch, need) in constraints.minCount { remaining += max(0, need - used[ch, default: 0]) }
        guard remaining == 0 else { return }
        for (tid, ch) in id2c where tid < logits.count {
            let allow = max(1, constraints.minCount[ch] ?? 0)
            if used[ch, default: 0] >= allow { logits[tid] = -1e30 }
        }
    }
    func forceDeficitIfNeeded(at pos: Int, constraints: MaskedConstraints, used: [Character:Int],
                              invMap: [Character:[Int]], logits: inout [Float]) {
        let remainingSlots = 5 - pos
        var deficit = 0; var keep: Set<Int> = []
        for (ch, minC) in constraints.minCount {
            let need = max(0, minC - used[ch, default: 0])
            if need > 0 { deficit += need; keep.formUnion(invMap[ch] ?? []) }
        }
        guard deficit > 0, deficit >= remainingSlots else { return }
        for i in 0..<logits.count where !keep.contains(i) { logits[i] = -1e30 }
    }
    func isAllowed(_ ch: Character, at position: Int, used: [Character:Int], constraints: MaskedConstraints) -> Bool {
        if constraints.disallow.contains(ch) { return false }
        if constraints.bannedAt[position].contains(ch) { return false }
        if let fx = constraints.fixed[position], fx != ch { return false }
        if let mx = constraints.maxCount[ch], used[ch, default: 0] >= mx { return false }
        return true
    }
    func invert(_ id2c: [Int: Character]) -> [Character:[Int]] {
        var out: [Character:[Int]] = [:]
        for (tid, ch) in id2c { out[ch, default: []].append(tid) }
        for (k, v) in out { out[k] = v.sorted() }
        return out
    }
    func filteredId2c(_ id2c: [Int: Character], vocab: Int) -> [Int: Character] {
        var out: [Int: Character] = [:]; out.reserveCapacity(min(id2c.count, vocab))
        for (tid, ch) in id2c where tid >= 0 && tid < vocab { out[tid] = ch }
        return out
    }
    func tokenStartsWithSpace(tokenId: Int) -> Bool { tokenizer.decode([tokenId]).first == " " }
    func pickFallbackChar(position: Int, used: [Character:Int], constraints: MaskedConstraints, lang: Language) -> Character {
        for ch in fallbackOrder(for: lang) {
            let need = constraints.minCount[ch, default: 0]
            if need > used[ch, default: 0], isAllowed(ch, at: position, used: used, constraints: constraints) { return ch }
        }
        for ch in fallbackOrder(for: lang) where used[ch, default: 0] == 0 {
            if isAllowed(ch, at: position, used: used, constraints: constraints) { return ch }
        }
        for ch in fallbackOrder(for: lang) {
            if isAllowed(ch, at: position, used: used, constraints: constraints) { return ch }
        }
        return (lang == .en) ? "e" : "י"
    }
    func fallbackOrder(for lang: Language) -> [Character] { lang == .en ? Array("etaoinshrdlcumwfgypbvkjxqz") : Array("יוהרלמאשתנכבדסגפצחעקטז") }
}

// MARK: - Model utils & sampling

extension WordleAI {
    static func findOptionalModelURL(named name: String) -> URL? {
        if ModelStorage.modelExists(name) { if let u = try? ModelStorage.modelDir(name: name) { return u } }
        let b = Bundle.main
        if let u = b.url(forResource: name, withExtension: "mlmodelc") { return u }
        if let all = b.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) {
            return all.first { $0.deletingPathExtension().lastPathComponent == name }
        }
        return nil
    }
    static func findTokenizerJSON(near anchor: URL?) throws -> URL {
        let fm = FileManager.default
        func probeDir(_ dir: URL) -> URL? {
            let candidates: [(String, String?)] = [
                ("tokenizer","json"),("tokenizer",nil),("tokenizer_config","json"),("tokenizer_config",nil),
                ("special_tokens_map","json"),("special_tokens_map",nil),("tokenizer","model"),
                ("config","json"),("config",nil),("WordleGPT_runtime_spec","json"),("WordleGPT_runtime_spec",nil)
            ]
            for (name, ext) in candidates {
                let u = (ext == nil) ? dir.appendingPathComponent(name) : dir.appendingPathComponent("\(name).\(ext!)")
                if fm.fileExists(atPath: u.path) { return u }
            }
            return nil
        }
        if let anchor {
            if let u = probeDir(anchor) { return u }
            if let u = probeDir(anchor.deletingLastPathComponent()) { return u }
        }
        if let root = try? ModelStorage.versionedRoot(),
           fm.fileExists(atPath: root.path),
           let u = probeDir(root) { return u }
        let b = Bundle.main
        let bundleCandidates: [(String, String?)] = [
            ("tokenizer","json"),("tokenizer",nil),("tokenizer_config","json"),("tokenizer_config",nil),
            ("special_tokens_map","json"),("special_tokens_map",nil),("tokenizer","model"),
            ("config","json"),("config",nil),("WordleGPT_runtime_spec","json"),("WordleGPT_runtime_spec",nil)
        ]
        for (name, ext) in bundleCandidates { if let u = b.url(forResource: name, withExtension: ext) { return u } }
        throw NSError(domain: "WordleAI", code: -11,
                      userInfo: [NSLocalizedDescriptionKey: "Tokenizer not found near model, in Models/vX/, or in bundle."])
    }
    func buildPrompt(history: [GuessHistory], lang: Language) -> String {
        let body = WordlePrompt.make(from: history)
        guard useLangTags else { return body }
        return ((lang == .en) ? "<|en|>\n" : "<|he|>\n") + body
    }
    static func extractKVOutputs(from out: MLFeatureProvider, vocab: Int, L: Int) -> ([Float],[MLMultiArray],[MLMultiArray])? {
        var kvTensors: [MLMultiArray] = []
        var logitsCandidate: MLMultiArray?
        var logitsScore = -1
        for name in out.featureNames {
            guard let ma = out.featureValue(for: name)?.multiArrayValue else { continue }
            let dims = ma.shape.map(\.intValue)
            let count = ma.count
            let lower = name.lowercased()
            if dims.count == 4 { kvTensors.append(ma); continue }
            var score = 0
            if lower.contains("logit") || lower.contains("lm_head") || lower.contains("probs") { score += 10 }
            if dims.last == vocab || dims.contains(vocab) { score += 5 }
            if vocab > 0 && (count == vocab || count % vocab == 0) { score += 3 }
            if dims.count <= 2 { score += 1 }
            if score > logitsScore { logitsCandidate = ma; logitsScore = score }
        }
        guard let lm = logitsCandidate, !kvTensors.isEmpty else { return nil }
        let mid = kvTensors.count / 2
        let ks = Array(kvTensors.prefix(mid))
        let vs = Array(kvTensors.suffix(from: mid))
        var flat = [Float](repeating: 0, count: lm.count)
        for i in 0..<lm.count { flat[i] = lm[i].floatValue }
        let logits: [Float]
        if flat.count == vocab { logits = flat }
        else if vocab > 0, flat.count % vocab == 0 { logits = Array(flat.suffix(vocab)) }
        else if let last = lm.shape.last?.intValue, flat.count % last == 0 { logits = Array(flat.suffix(last)) }
        else { logits = flat }
        return (logits, ks, vs)
    }
    func sampleRestricted(logits: [Float], candidates: [Int], temperature: Float, topK: Int) -> Int {
        var idxs: [Int] = []
        for id in candidates where id >= 0 && id < logits.count { idxs.append(id) }
        guard !idxs.isEmpty else { return 0 }
        if temperature <= 0 {
            var best = idxs[0], bestVal = logits[best]
            for id in idxs where logits[id] > bestVal { best = id; bestVal = logits[id] }
            return best
        }
        let k = max(1, min(topK, idxs.count))
        idxs.sort { logits[$0] > logits[$1] }
        let top = Array(idxs.prefix(k))
        var mx: Float = -Float.infinity
        let invT = 1 / max(temperature, 1e-6)
        for id in top { mx = max(mx, logits[id] * invT) }
        var exps = [Float](); exps.reserveCapacity(k)
        var sum: Float = 0
        for id in top { let v = expf(logits[id] * invT - mx); exps.append(v); sum += v }
        var r = Float.random(in: 0..<1)
        for (j, v) in exps.enumerated() { r -= v / sum; if r <= 0 { return top[j] } }
        return top.last!
    }
}

// MARK: - Convenience Provider

final class WordleAIProvider: Singleton {
    private var loadTask: Task<WordleAI, Error>?
    private var ai: WordleAI?
    
    static var aiWarmedup: Bool { shared.ai != nil ? !shared.ai!.needWarmup : false }
    
    private override init() {}
    
    func sharedAsync() async -> WordleAI {
        if let ai { return ai }
        do {
            if let t = loadTask { return try await t.value }
            let t = Task(priority: .userInitiated) { () throws -> WordleAI in
                let built = try WordleAI.make()
                await MainActor.run { self.ai = built }
                return built
            }
            loadTask = t
            defer { loadTask = nil }
            return try await t.value
        } catch { fatalError("-- AI can not be initialize --") }
    }
    
    func deassign() { ai = nil }
}
