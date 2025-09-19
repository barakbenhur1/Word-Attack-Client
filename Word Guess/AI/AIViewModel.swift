//
//  WordZapViewModel.swift
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

@Observable
class AIViewModel {
    // MARK: - Private Parameters
    private typealias BossProvider = (() -> String?)
    private let lang: Language
    private let phraseProvider: PhraseProvider
    private var history: [GuessHistory]
    private var solverWarmedup: Bool = false
    private var bossProvider: BossProvider = { nil } {
        didSet {
            installBossEnhancementProvider(bossProvider: bossProvider)
        }
    }
    
    // MARK: - Public Parameters
    var isReadyToGuess: Bool { solverWarmedup }
    var phrase: String { phraseProvider.phrase }
    var showPhraseValue: Bool { phraseProvider.showPhraseValue }
    
    init(language: Language, startingHistory: [GuessHistory] = []) {
        lang = language
        history = startingHistory
        phraseProvider = PhraseProvider()
        solverWarmedup = WordZapAIProvider.shared.aiWarmedup
        Task(priority: .high) { [weak self] in
            guard let self else { return }
            guard !solverWarmedup  else { return }
            await solver().warmUp()
            await MainActor.run { [weak self] in
                guard let self else { return }
                solverWarmedup = true
            }
        }
    }
}

// MARK: - Public
@MainActor
extension AIViewModel {
    func saveToHistory(guess: GuessHistory) { history.append(guess) }
    func deassign() { WordZapAIProvider.shared.deassign() }
    func startShowingPhrase() { phraseProvider.startShowingPhrase() }
    func hidePhrase() { phraseProvider.hidePhrase() }
    func manageMemory(with guessHistory: [GuessHistory] = [], provider: @escaping (() -> String?) = { nil }) {
        bossProvider = provider
        history = guessHistory
    }
    func addDetachedFirstGuess(with formatter: @escaping (_ value: String) -> GuessHistory?) async {
        guard let guess = try? await solver().pickFirstGuessFromModel(lang: lang) else { return }
        guard let formattedGuess = formatter(guess.map { String($0).returnChar(isFinal: $0 == guess.last) }.joined()) else { return }
        saveToHistory(guess: formattedGuess)
    }
}

// MARK: - Private
extension AIViewModel {
    private func solver() async -> WordZapAI { await WordZapAIProvider.shared.sharedAsync() }
    private func fallbackGuess() -> String { return generateWord(for: lang, length: 5) }
    func getFeedback(for difficulty: AIDifficulty) async -> String {
        do {
            return try await solver().guessNext(history: history,
                                                lang: lang,
                                                difficulty: difficulty)
        } catch { fatalError("Solver Faild Return Word!!!") /*return generateWord(for: lang)*/ }
    }
    private func installBossEnhancementProvider(bossProvider: @escaping BossProvider) {
        Task.detached(priority: .high) { [weak self] in
            guard let self else { return }
            await solver().installBossEnhancementProvider(bossProvider)
        }
    }
}

