//
//  WordZapViewModel.swift
//  WordZap
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
    private var solver: WordZapAI?
    private var history: [GuessHistory]
    private var solverWarmedup: Bool = false
    private var bossProvider: BossProvider = { nil } {
        didSet { installBossEnhancementProvider(bossProvider: bossProvider) }
    }
    
    // MARK: - Public Parameters
    var isReadyToGuess: Bool { solverWarmedup }
    var phrase: String { phraseProvider.phrase }
    var showPhraseValue: Bool { phraseProvider.showPhraseValue }
    
    init(language: Language, startingHistory: [GuessHistory] = []) {
        lang           = language
        history        = startingHistory
        phraseProvider = PhraseProvider()
        handleSolver()
    }
    
    private func handleSolver() {
        let provider = WordZapAIProvider.shared
        solverWarmedup = provider.aiReady
        guard !solverWarmedup else { solver = provider.fetch(); return }
        // Warm-up off the main actor; hop back only to update state.
        Task.detached(priority: .high) {
            guard let s = provider.fetch() else { return }
            s.warmUp()
            await MainActor.run { [weak self] in
                guard let self else { return }
                solver = s
                solverWarmedup = provider.aiReady
            }
        }
    }
}

// MARK: - Public
extension AIViewModel {
    func saveToHistory(guess: GuessHistory) { history.append(guess) }
    func startShowingPhrase() { phraseProvider.startShowingPhrase() }
    func hidePhrase() { phraseProvider.hidePhrase() }
    
    func manageMemory(with guessHistory: [GuessHistory] = [], provider: @escaping (() -> String?) = { nil }) {
        bossProvider = provider
        history = guessHistory
    }
    
    func addDetachedFirstGuess(with formatter: @escaping (_ value: String) -> GuessHistory?) async {
        guard let solver else { return }
        guard let guess = try? solver.pickFirstGuessFromModel(lang: lang) else { return }
        let animated = guess.map { String($0).returnChar(isFinal: $0 == guess.last) }.joined()
        guard let formatted = formatter(animated) else { return }
        saveToHistory(guess: formatted)
    }
    
    func getFeedback(for difficulty: AIDifficulty) async -> String? {
        guard let solver else { return nil }
        do { return try solver.guessNext(history: history, lang: lang, difficulty: difficulty) }
        catch {
            #if DEBUG
            fatalError(error.localizedDescription)
            #else
            return generateWord(for: lang)
            #endif
        }
    }
    
    @MainActor
    func release() {
        phraseProvider.hidePhrase()
        phraseProvider.stop()
        solver = nil
        WordZapAIProvider.shared.release()
    }
}

// MARK: - Private
private extension AIViewModel {
    private func fallbackGuess() -> String { generateWord(for: lang, length: 5) }
    private func installBossEnhancementProvider(bossProvider: @escaping BossProvider) {
        solver?.installBossEnhancementProvider(bossProvider)
    }
}
