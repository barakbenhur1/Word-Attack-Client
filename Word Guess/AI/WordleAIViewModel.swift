//
//  WordleViewModel.swift
//  Word Guess
//  Created by Barak Ben Hur on 04/08/2025.
//

import SwiftUI

/// Little helper for UI/testing (not used by core engine).
public func generateWord(for lang: Language, length: Int = 5) -> String {
    let en = Array("abcdefghijklmnopqrstuvwxyz")
    let he = Array("אבגדהוזחטיכלמנסעפצקרשת")
    let alpha = (lang == .en) ? en : he
    return (0..<length).compactMap { _ in alpha.randomElement() }.map(String.init).joined()
}

@MainActor
@Observable
class WordleAIViewModel {
    private let lang: Language
    private var history: [GuessHistory]
    
    private var warmedUp = false
    
    var isReadyToGuess: Bool { warmedUp }
    
    init(language: Language, startingHistory: [GuessHistory] = []) {
        lang = language
        history = startingHistory
        Task(priority: .userInitiated) {
            await solver().warmUp()
            warmedUp = true
            Trace.log("⚡️", "AI warmed up", Fancy.green)
        }
    }
    
    // MARK: - Public
    
    func cleanHistory(with guessHistory: [GuessHistory] = []) { history = guessHistory }
    
    func addDetachedGuess(with formatter: @escaping (_ value: String) -> GuessHistory) {
        Task(priority: .userInitiated) {
            guard let guess = try? await solver().pickFirstGuessFromModel(lang: lang) else { return }
            history = [formatter(guess.map { String($0).returnChar(isFinal: $0 == guess.last) }.joined())]
        }
    }
    
    func submitFeedback(guess: [GuessHistory], difficulty: AIDifficulty) async -> String {
        saveToHistory(guess: guess)
        return await takeGuess(difficulty: difficulty)
    }
    
    func deassign() { WordleAIProvider.shared.deassign() }
    
    // MARK: - Private
    
    private func solver() async -> WordleAI { await WordleAIProvider.shared.sharedAsync() }
    
    private func saveToHistory(guess: [GuessHistory]) { history.append(contentsOf: guess) }
    
    private func fallbackGuess() -> String { return generateWord(for: lang, length: 5) }
    
    private func takeGuess(difficulty: AIDifficulty) async -> String {
        let task = Task.detached(priority: .high) { [weak self] () -> String in
            do {
                guard let self else { fatalError("Solver is not avilbale") }
                return try await solver().guessNext(history: history,
                                                    lang: lang,
                                                    difficulty: difficulty)
            } catch { fatalError("Solver faild to provide a guess") }
        }
        
        return await task.value
    }
}
