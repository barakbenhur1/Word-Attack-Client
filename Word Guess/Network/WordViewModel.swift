//
//  VIewModel.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI
import Alamofire

enum WordLanguage: String {
    case en, he
}

@Observable
class WordViewModel: ViewModel {
    private let network: Network
    var word: WordData
    var isError: Bool
    
    override var wordValue: String { word.word.value }
    
    required override init() {
        network = Network(root: "words")
        word = .empty
        isError = false
    }
    
    func initMoc() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            let local = LanguageSetting()
            let language = local.locale.identifier.components(separatedBy: "_").first
            withAnimation { self.word = .init(score: 0, word: .init(value: language == "he" ? "אבגדה" : "abcde", guesswork: []), number: 0, isTimeAttack: false) }
        }
    }
    
    func word(diffculty: DifficultyType, email: String) async {
        guard diffculty != .tutorial else {
            let local = LanguageSetting()
            let language = local.locale.identifier.components(separatedBy: "_").first
            return word = .init(score: 0,
                                word: .init(value: language == "he" ? "שלום" : "Cool",
                                            guesswork: []),
                                number: 0,
                                isTimeAttack: false)
        }
        
        let value: WordData? = await network.send(route: "getWord",
                                                  parameters: ["diffculty": diffculty.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                                               "email": email])
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard let value else { return isError = true }
#if DEBUG
            Trace.log("🛟", "Word is \(value.word.value)", Fancy.mag)
#endif
            withAnimation { self.word = value }
        }
    }
    
    func addGuess(diffculty: DifficultyType, email: String, guess: String) async {
        let value: EmptyModel? = await network.send(route: "addGuess",
                                                    parameters: ["diffculty": diffculty.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                 "email": email,
                                                                 "guess": guess])
        
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard value != nil else { return isError = true }
        }
    }
    
    func score(diffculty: DifficultyType, email: String) async {
        let value: EmptyModel? = await network.send(route: "score",
                                                    parameters: ["diffculty": diffculty.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                 "email": email])
        
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard value != nil else { return isError = true }
        }
    }
}

extension String {
    func removingEmojis() -> String {
        return self.unicodeScalars.filter {
            // Exclude characters that are emojis or emoji components
            !$0.properties.isEmojiPresentation &&
            !$0.properties.isEmoji &&
            $0 != "\u{200D}" // Zero Width Joiner
        }.reduce(into: "") { $0.append(String($1)) }
    }
}
