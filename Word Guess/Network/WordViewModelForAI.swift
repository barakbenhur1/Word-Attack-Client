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
    private let network: Network
    var word: WordForAiMode
    var isError: Bool
    var aiDownloaded: Bool = ModelStorage.localHasUsableModels()
    
    override var wordValue: String { word.value }
    
    required override init() {
        network = Network(root: "words")
        word = .empty
        aiDownloaded = false
        isError = false
    }
    
    
    func initMoc() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            let local = LanguageSetting()
            let language = local.locale.identifier.components(separatedBy: "_").first
            withAnimation { self.word = .init(value: language == "he" ? "אבגדה" : "abcde") }
        }
    }
    
    func word(email: String) async {
        let value: WordForAiMode? = await network.send(route: "word",
                                                              parameters: ["email": email])
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard let value else { return isError = true }
            Trace.log("🛟", "word is \(value.value)", Fancy.mag)
            withAnimation { self.word = value }
        }
    }
    
    // MARK: - Public: enumerate ALL per-index best merges (Y/G only, deduped)
    func perIndexCandidatesSparse(matrix: [[String]], colors: [[CharColor]],
                                  aiMatrix: [[String]], aiColors: [[CharColor]]) -> [BestGuess] {
        return BestGuessProducerProvider.guesser.perIndexCandidatesSparse(matrix: matrix, colors: colors,
                                                                aiMatrix: aiMatrix, aiColors: aiColors,
                                                                /*debug: true*/)
    }
}
