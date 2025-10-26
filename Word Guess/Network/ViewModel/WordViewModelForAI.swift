//
//  ViewModelForAI.swift
//  wordForAI Guess
//
//  Created by Barak Ben Hur on 17/08/2025.
//

import SwiftUI
import Alamofire

@Observable
class AIWordViewModel: WordViewModel {
    private let provider: WordProvider
    var aiDownloaded: Bool = false
    
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
        aiDownloaded = true
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
