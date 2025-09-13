//
//  PremiumGameViewModel.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 11/09/2025.
//

import SwiftUI
import Alamofire

@Observable
class PremiumHubViewModel: ViewModel {
    private let scoreProvider: PremiumScoreProvider
    private let wordProvider: WordProvider
    var word: SimpleWord
    
    override var wordValue: String { word.value }
    
    required override init() {
        scoreProvider = .init()
        wordProvider = .init()
        word = .empty
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
        word = .empty
        let value: SimpleWord? = await wordProvider.word(email: email)
        
        guard let value else { await initMoc(); return }
        await MainActor.run { [weak self] in
            guard let self else { return }
            Trace.log("🛟", "word is \(value.value)", Fancy.mag)
            word = value
        }
    }
    
    func getScore(email: String) async -> Int {
        let score = await scoreProvider.getPremium(email: email)?.value ?? 0
        return score
    }
}
