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
    // MARK: - Private Parameters
    private let lang: Language
    private var history: [GuessHistory]
    private var solverWarmedup: Bool = false
    private let phraseProvider = PhraseProvider()
    
    private var bossProvider: (() -> String?) = { nil } {
        didSet {
            Task.detached(priority: .high) { [weak self] in
                guard let self else { return }
                await solver().installBossEnhancementProvider(bossProvider)
            }
        }
    }
    
    // MARK: - Public Parameters
    var isReadyToGuess: Bool { solverWarmedup }
    
    var phrase: String { phraseProvider.phrase }
    
    var showPhraseValue: Bool { phraseProvider.showPhraseValue }
    
    init(language: Language, startingHistory: [GuessHistory] = []) {
        lang = language
        history = startingHistory
        solverWarmedup = WordleAIProvider.aiWarmedup
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard !solverWarmedup  else { return }
            await solver().warmUp()
            solverWarmedup = true
        }
    }
    
    func manageMemory(with guessHistory: [GuessHistory] = [], provider: @escaping (() -> String?) = { nil }) {
        bossProvider = provider
        history = guessHistory
    }
    
    func addDetachedFirstGuess(with formatter: @escaping (_ value: String) -> GuessHistory?) {
        Task(priority: .high) { [weak self] in
            guard let self else { return }
            guard let guess = try? await solver().pickFirstGuessFromModel(lang: lang) else { return }
            guard let formattedGuess = formatter(guess.map { String($0).returnChar(isFinal: $0 == guess.last) }.joined()) else { return }
            saveToHistory(guess: formattedGuess)
        }
    }
    
    func saveToHistory(guess: GuessHistory) { history.append(guess) }
    
    func deassign() { WordleAIProvider.shared.deassign() }
    
    func startShowingPhrase() { phraseProvider.startShowingPhrase() }
    
    func hidePhrase() { phraseProvider.hidePhrase() }
    
    // MARK: - Private
    
    private func solver() async -> WordleAI { await WordleAIProvider.shared.sharedAsync() }
    
    private func fallbackGuess() -> String { return generateWord(for: lang, length: 5) }
    
    func getFeedback(with difficulty: AIDifficulty) async -> String {
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
