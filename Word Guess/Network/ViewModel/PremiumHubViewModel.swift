//
//  PremiumGameViewModel.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 11/09/2025.
//

import SwiftUI
import Alamofire

@Observable
class PremiumHubViewModel: WordViewModel {
    private let scoreProvider: PremiumScoreProvider
    private let wordProvider: WordProvider
    var isError: Bool
    var word: SimpleWord
    
    override var wordValue: String { word.value }
    
    required override init() {
        scoreProvider = .init()
        wordProvider = .init()
        isError = false
        word = .empty
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
        word = .empty
        let value: SimpleWord? = await wordProvider.word(email: email)
        
        guard let value else { isError = true; return }
        await MainActor.run { [weak self] in
            guard let self else { return }
            Trace.log("🛟", "word is \(value.value)", Fancy.mag)
            word = value
        }
    }
    
    func getScore(email: String) async -> PremiumScoreData? {
        let score = await scoreProvider.getPremium(email: email)
        return score
    }
}
