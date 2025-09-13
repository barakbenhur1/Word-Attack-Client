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
    var word: SimpleWord
    var aiDownloaded: Bool = ModelStorage.localHasUsableModels()
    var fatalError: Bool { errorCount >= maxErrorCount }
    var numberOfErrors: Int { errorCount }
    
    private let maxErrorCount: Int
    private var errorCount: Int
    
    override var wordValue: String { word.value }
    
    required override init() {
        network = Network(root: "words")
        word = .empty
        aiDownloaded = false
        maxErrorCount = 3
        errorCount = 0
    }
    
    func initMoc() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            let local = LanguageSetting()
            let language = local.locale.identifier.components(separatedBy: "_").first
            word = .init(value: language == "he" ? "אבגדה" : "abcde")
        }
    }
    
    func word(email: String) async {
        let value: SimpleWord? = await network.send(route: "word",
                                                       parameters: ["email": email])
        
        guard let value else { return await handleError() }
        await MainActor.run { [weak self] in
            guard let self else { return }
            Trace.log("🛟", "word is \(value.value)", Fancy.mag)
            word = value
            errorCount = 0
        }
    }
    
    // MARK: - Public: enumerate ALL per-index best merges (Y/G only, deduped)
    func perIndexCandidatesSparse(matrix: [[String]], colors: [[CharColor]],
                                  aiMatrix: [[String]], aiColors: [[CharColor]]) -> [BestGuess] {
        return BestGuessProducerProvider.guesser.perIndexCandidatesSparse(matrix: matrix, colors: colors,
                                                                aiMatrix: aiMatrix, aiColors: aiColors,
                                                                /*debug: true*/)
    }
    
    private func handleError() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            word = .empty
            errorCount += 1
        }
    }
}
