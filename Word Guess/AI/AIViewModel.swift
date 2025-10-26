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
//    private var solver: WordZapAI?
    private var provider: AIProvider
    private var history: [GuessHistory]
    private var solverWarmedup: Bool = false
    private var bossProvider: BossProvider = { nil } {
        didSet { installBossEnhancementProvider(bossProvider: bossProvider) }
    }
    
    // MARK: - Public Parameters
    var isReadyToGuess: Bool { solverWarmedup }
    @MainActor var phrase: String { phraseProvider.phrase }
    var showPhraseValue: Bool { phraseProvider.showPhraseValue }
    
    init(language: Language, startingHistory: [GuessHistory] = []) {
        lang           = language
        history        = startingHistory
        phraseProvider = PhraseProvider()
        provider = .init()
        warmUP()
    }
    
    private func warmUP() {
        let provider = provider
        Task.detached(priority: .utility) {
            let value = await provider.warmUpAi()
            await MainActor.run { [weak self] in
                guard let self else { return }
                solverWarmedup = value
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
//        guard let solver else { return }
//        guard let guess = try? solver.pickFirstGuessFromModel(lang: lang) else { return }
//        let animated = guess.map { String($0).returnChar(isFinal: $0 == guess.last) }.joined()
//        guard let formatted = formatter(animated) else { return }
        //        saveToHistory(guess: formatted)
    }
    
    func getFeedback(for difficulty: AIDifficulty) async -> String? {
        let value = await provider.aiWord(history: history, lang: lang, difficulty: difficulty)
        let guess = value?.guess
        
        guard let guess else {
#if DEBUG
            fatalError("No Ai Word!!!")
#else
            return generateWord(for: lang)
#endif
        }
        
        return guess
    }
    
    @MainActor
    func release() {
        phraseProvider.hidePhrase()
        phraseProvider.stop()
//        solver = nil
        WordZapAIProvider.shared.release()
    }
}

// MARK: - Private
private extension AIViewModel {
    private func fallbackGuess() -> String { generateWord(for: lang, length: 5) }
    private func installBossEnhancementProvider(bossProvider: @escaping BossProvider) {
//        solver?.installBossEnhancementProvider(bossProvider)
    }
}
