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
class DifficultyWordViewModel: WordViewModel {
    private let wordService: WordService
    private let scoreService: ScoreService
    var word: WordData
    var score: Int
    var isError: Bool
    
    override var wordValue: String { word.word.value }
    
    required override init() {
        wordService = .init()
        scoreService = .init()
        word = .empty
        score = 0
        isError = false
    }
    
    func initMoc(diffculty: DifficultyType) async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            word = wordService.initMoc(diffculty: diffculty)
        }
    }
    
    func word(diffculty: DifficultyType, email: String) async {
        switch diffculty {
        case .tutorial:
            let local = LanguageSetting()
            let language = local.locale.identifier.components(separatedBy: "_").first
            await MainActor.run { [weak self] in
                guard let self else { return }
                word = .init(word: .init(value: language == "he" ? "שלום" : "Cool", guesswork: []), number: 0, isTimeAttack: false)
            }
        default:
            let value  = await wordService.word(diffculty: diffculty, email: email)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let value else { isError = true; return }
                Trace.log("🛟", "Word is \(value.word.value)", Fancy.mag)
                word = value
            }
        }
    }
    
    func addGuess(diffculty: DifficultyType, email: String, guess: String) async {
        switch diffculty {
        case .tutorial: break
        default:
            let value: EmptyModel? = await wordService.addGuess(diffculty: diffculty, email: email, guess: guess)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard value != nil else { isError = true; return }
            }
        }
    }
    
    func score(diffculty: DifficultyType, email: String, isCorrect: Bool) async {
        guard isCorrect else { return }
        let value: EmptyModel? = await scoreService.score(diffculty: diffculty, email: email)
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard value != nil else { return isError = true }
        }
    }
    
    func getScore(diffculty: DifficultyType, email: String) async  {
        switch diffculty {
        case .tutorial:
            await MainActor.run { [weak self] in
                guard let self else { return }
                score = 0
            }
        default:
            let value: ScoreData? = await scoreService.getScore(diffculty: diffculty, email: email)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let value else { score = 0; return }
                score = value.score
            }
        }
    }
}

fileprivate protocol Service { var network: Network { get } }

fileprivate class ScoreService: Service {
    fileprivate let network: Network
    
    required init() {
        network = Network(root: .score)
    }
    
    func score(diffculty: DifficultyType, email: String) async -> EmptyModel? {
        let value: EmptyModel? = await network.send(route: .score,
                                                    parameters: ["diffculty": diffculty.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                 "email": email])
        return value
    }
    
    func getScore(diffculty: DifficultyType, email: String) async -> ScoreData? {
        let value: ScoreData? = await network.send(route: .getScore,
                                                   parameters: ["diffculty": diffculty.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                 "email": email])
        return value
    }
    
    func getPlaceInLeaderboard(email: String) async -> LeaderboaredPlaceData? {
        let value: LeaderboaredPlaceData? = await network.send(route: .place,
                                                               parameters: ["email": email])
        return value
    }
}

fileprivate class WordService: Service {
    fileprivate let network: Network
   
    required init() {
        network = Network(root: .words)
    }
    
    func initMoc(diffculty: DifficultyType) -> WordData {
        let local = LanguageSetting()
        guard let language = local.locale.identifier.components(separatedBy: "_").first else { return .init(word: .init(value: "abcde", guesswork: []), number: 0, isTimeAttack: false) }
        guard let l: Language = .init(rawValue: language) else { return .init(word: .init(value: language == "he" ? "אבגדה" : "abcde", guesswork: []), number: 0, isTimeAttack: false) }
        return .init(word: .init(value:  generateWord(for: l, length: diffculty.getLength()), guesswork: []), number: 0, isTimeAttack: false)
    }
    
    func word(diffculty: DifficultyType, email: String) async -> WordData? {
        let value: WordData? = await network.send(route: .getWord,
                                                  parameters: ["diffculty": diffculty.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                                               "email": email])
        return value
    }
    
    func addGuess(diffculty: DifficultyType, email: String, guess: String) async -> EmptyModel? {
        let value: EmptyModel? = await network.send(route: .addGuess,
                                                    parameters: ["diffculty": diffculty.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                                                 "email": email,
                                                                 "guess": guess])
        return value
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
