//
//  ViewModelForAI.swift
//  wordForAI Guess
//
//  Created by Barak Ben Hur on 17/08/2025.
//

import SwiftUI
import Alamofire

// MARK: - Public API

public struct GuessRow: Codable {
    let word: String
    let feedback: String
}
 
protocol Health: Codable {
    var ok: Bool { get }
}

public struct HealthLite: Health {
    public let ok: Bool
    public let warmed: Bool?
    public let backend: String?
    public let storage: String?
    public let modelLoadMode: String?
    public let modelOnDisk: Bool?
    public let tokenizerOnDisk: Bool?
    public let memoryMB: MemoryMB?
    public struct MemoryMB: Codable { public let rss, heapUsed, heapTotal, external: Int }
}

public struct HealthFull: Health {
    public let ok: Bool
    public let warmed: Bool
    public let backend: String
    public let storage: String
    public let modelPath: String?
    public let tokenizerPath: String?
    public let vocabSize: Int
    public let lettersEN: Int
    public let lettersHE: Int
    public let wordsEN: Int
    public let wordsHE: Int
}

public typealias GuessHistory = (word: String, feedback: String)

public extension Array where Element == GuessHistory {
    var jsonValid: [GuessRow] { map { GuessRow(word: $0.word, feedback: String($0.feedback.map { $0 == "🟩" ? "G" : $0 == "🟨" ? "Y" : "-" })) } }
}

public typealias AIDifficultyItem = (image: String, name: String, color: Color)

public enum AIDifficulty {
    case easy, medium, hard, boss
    typealias RawValue = AIDifficultyItem
    var name: String { rawValue.name }
    var image: String { rawValue.image }
    var color: Color { rawValue.color }
    
    init?(rawValue: AIDifficultyItem) {
        switch rawValue {
        case ("easyAI", "Chad GPT", .green):     self = .easy
        case ("mediumAI", "Hell 9000", .yellow): self = .medium
        case ("hardAI", "Spynet", .orange):      self = .hard
        case ("bossAI", "This Guy", .red):       self = .boss
        default:                                 fatalError()
        }
    }
    
    var stringValue: String {
        switch self {
        case .easy:   "easy"
        case .medium: "medium"
        case .hard:   "hard"
        case .boss:   "boss"
        }
    }
    
    var rawValue: AIDifficultyItem {
        switch self {
        case .easy:   ("easyAI", "Chad GPT", .green)
        case .medium: ("mediumAI", "Hell 9000", .yellow)
        case .hard:   ("hardAI", "Spynet", .orange)
        case .boss:   ("bossAI", "This Guy", .red)
        }
    }
    
    var params: (temperature: Float, topK: Int) {
        switch self {
        case .easy:        (0.70, 32)
        case .medium:      (0.40, 12)
        case .hard, .boss: (0.00, 1)
        }
    }
    
    var premiumLetterCount: Int {
        switch self {
        case .easy:   2
        case .medium: 3
        case .hard:   4
        case .boss:   5
        }
    }
}

@Observable
class AIGameViewModel: GameViewModel {
    private let provider: WordProvider
    
    private let maxErrorCount: Int
    private var errorCount: Int
    var fatalError: Bool { errorCount >= maxErrorCount }
    var numberOfErrors: Int { errorCount }
    
    private var wordNumber: Int
    var wordCount: Int { wordNumber }
    
    private var aiWord: SimpleWord
    var word: SimpleWord { aiWord }
    override var wordValue: String { aiWord.value }
    
    required override init() {
        provider = .init()
        aiWord = .empty
        wordNumber = UserDefaults.standard.integer(forKey: "aiWordNumber")
        maxErrorCount = 3
        errorCount = 0
    }
    
    func initMoc() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            let local = LanguageSetting()
            guard let language = local.locale.identifier.components(separatedBy: "_").first else { aiWord = .init(value: "abcde"); return }
            guard let l: Language = .init(rawValue: language) else { aiWord = .init(value: language == "he" ? "אבגדה" : "abcde"); return }
            aiWord = .init(value: generateWord(for: l))
        }
    }
    
    func word(uniqe: String, newWord: Bool = true) async {
        let value: SimpleWord? = await provider.word(uniqe: uniqe)
        guard let value else { await handleError(); return }
        await MainActor.run { [weak self] in
            guard let self else { return }
            Trace.log("🛟", "word is \(value.value)", Fancy.mag)
            errorCount = 0
            aiWord = value
            
            guard newWord else { return }
            incraseAndSaveWordNumber()
        }
    }
    
    // MARK: - Public: enumerate ALL per-index best merges (Y/G only, deduped)
    func perIndexCandidatesSparse(matrix: [[String]], colors: [[CharColor]],
                                  aiMatrix: [[String]], aiColors: [[CharColor]]) -> [BestGuess] {
        return BestGuessProducerProvider.guesser.perIndexCandidatesSparse(matrix: matrix, colors: colors,
                                                                          aiMatrix: aiMatrix, aiColors: aiColors,
                                                                          /*debug: true*/)
    }
    
    @MainActor
    private func handleError() {
        errorCount += 1
        aiWord = .empty
    }
    
    @MainActor
    private func incraseAndSaveWordNumber() {
        guard aiWord != .empty else { return }
        wordNumber += 1
        UserDefaults.standard.set(wordNumber, forKey: "aiWordNumber")
    }
}
