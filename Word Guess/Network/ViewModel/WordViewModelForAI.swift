//
//  ViewModelForAI.swift
//  wordForAI Guess
//
//  Created by Barak Ben Hur on 17/08/2025.
//

import SwiftUI
import Alamofire

@Observable
class WordViewModelForAI: ViewModel {
    private let provider: WordProvider
    var word: SimpleWord
    var aiDownloaded: Bool = false
    var fatalError: Bool { errorCount >= maxErrorCount }
    var numberOfErrors: Int { errorCount }
    
    private let maxErrorCount: Int
    private var errorCount: Int
    
    override var wordValue: String { word.value }
    
    required override init() {
        provider = .init()
        word = .empty
        maxErrorCount = 3
        errorCount = 0
        aiDownloaded = ModelStorage.localHasUsableModels()
    }
    
    func initMoc() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            let local = LanguageSetting()
            guard let language = local.locale.identifier.components(separatedBy: "_").first else { word = .init(value: "abcde"); return }
            guard let l: Language = .init(rawValue: language) else { word = .init(value: language == "he" ? "אבגדה" : "abcde"); return }
            word = .init(value: generateWord(for: l))
        }
    }
    
    func word(email: String) async {
        let value: SimpleWord? = await provider.word(email: email)
        guard let value else { await handleError(); return }
        await MainActor.run { [weak self] in
            guard let self else { return }
            Trace.log("🛟", "word is \(value.value)", Fancy.mag)
            errorCount = 0
            word = value
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
        word = .empty
    }
}
