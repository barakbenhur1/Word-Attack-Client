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
class ViewModel: ObservableObject {
    private let network: Network
    var word: WordData
    var isError: Bool
    var current: Int
    var aiDownloaded: Bool = ModelStorage.localHasUsableModels()
    
    required init() {
        network = Network(root: "words")
        word = .emapty
        current = 0
        aiDownloaded = false
        isError = false
    }
    
    
    func initMoc() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            withAnimation { self.word = .init(score: 0, word: .init(value: "abcde", guesswork: []), number: 0, isTimeAttack: false) }
        }
    }
    
    func wordForAiMode(email: String) async {
        let word: WordForAiMode? = await network.send(route: "word",
                                                      parameters: ["email": email])
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard let word else { return isError = true }
            withAnimation { self.word = .init(score: 0, word: .init(value: word.value, guesswork: []), number: 0, isTimeAttack: false) }
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
            withAnimation { self.word = value }
        }
    }
    
    func addGuess(diffculty: DifficultyType, email: String, guess: String) async {
        let value: EmptyModel? = await network.send(route: "addGuess",
                                                    parameters: ["diffculty": diffculty.rawValue.removingEmojis().trimmingCharacters(in: .whitespacesAndNewlines),
                                                                 "email": email,
                                                                 "guess": guess])
        
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard value != nil else { return isError = true }
        }
    }
    
    func score(diffculty: DifficultyType, email: String) async {
        let value: EmptyModel? = await network.send(route: "score",
                                                    parameters: ["diffculty": diffculty.rawValue.removingEmojis().trimmingCharacters(in: .whitespacesAndNewlines),
                                                                 "email": email])
        
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard value != nil else { return isError = true }
        }
    }
    
    func calcGuess(word: [String], length: Int) -> [CharColor] {
        var colors = [CharColor](repeating: .noMatch,
                                 count: length)
        var containd = [String: Int]()
        
        for char in self.word.word.value.lowercased() {
            let key = String(char).returnChar(isFinal: false)
            if containd[key] == nil { containd[key] = 1 }
            else { containd[key]! += 1 }
        }
        
        for i in 0..<word.count {
            if word[i].lowercased().isEquel(self.word.word.value[i].lowercased()) {
                containd[word[i].lowercased().returnChar(isFinal: false)]! -= 1
                colors[i] = .exactMatch
            }
        }
        
        for i in 0..<word.count {
            guard !word[i].lowercased().isEquel(self.word.word.value[i].lowercased()) else { continue }
            if self.word.word.value.lowercased().toSuffixChars().contains(word[i].lowercased().returnChar(isFinal: true)) && containd[word[i].lowercased().returnChar(isFinal: false)]! > 0 {
                containd[word[i].lowercased().returnChar(isFinal: false)]! -= 1
                colors[i] = .partialMatch
            } else { colors[i] = .noMatch }
        }
        
        return colors
    }
    
    // MARK: - Public: enumerate ALL per-index best merges (Y/G only, deduped)
    func allBestGuesses(matrix: [[String]], colors: [[CharColor]], aiMatrix: [[String]], aiColors: [[CharColor]]
    ) -> [[Guess]] {
        return BestGuessProducerProvider.guesser.allBestGuesses(matrix: matrix,
                                                               colors: colors,
                                                               aiMatrix: aiMatrix,
                                                               aiColors: aiColors,
                                                               debug: true)
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
