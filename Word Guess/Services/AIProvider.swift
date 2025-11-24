//
//  AIProvider.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 26/10/2025.
//

import Observation
import Foundation

typealias BossProvider = (() -> String?)

class AIProvider {
    let network: Network
    
    private var cheat: BossProvider? = nil
    
    init() {
        network = Network(root: .ai)
    }
    
    private struct AIGuessRequest: Codable {
        let lang: String       // "en" | "he"
        let difficulty: String // "easy" | "medium" | "hard" | "boss"
        let history: [GuessRow]
    }
    
    private struct BossAIGuessRequest: Codable {
        let lang: String       // "en" | "he"
        let difficulty: String // "easy" | "medium" | "hard" | "boss"
        let history: [GuessRow]
        var cheat: String?
    }
    
    func installBossEnhancementProvider(_ c: BossProvider?) {
        cheat = c
    }
    
    private func makeAIGuessBody(
        lang: String,
        difficulty: String,
        cheat: String?,
        history: [GuessRow]
    ) throws -> Data {
        if let cheat, difficulty == "boss" {
            let req  = BossAIGuessRequest(lang: lang, difficulty: difficulty, history: history, cheat: cheat)
            let enc  = JSONEncoder()
            return try enc.encode(req)
        } else {
            let req = AIGuessRequest(lang: lang, difficulty: difficulty, history: history)
            let enc  = JSONEncoder()
            return try enc.encode(req)
        }
    }
    
    func aiWord(history: [GuessHistory], lang: Language , difficulty: AIDifficulty) async -> AiWord? {
        guard let parameters = try? makeAIGuessBody(lang: lang.rawValue,
                                                    difficulty: difficulty.stringValue,
                                                    cheat: cheat?(),
                                                    history: history.jsonValid) else { return nil }
        
        let value: AiWord? = await network.send(route: .aiGuess,
                                                parameters: parameters)
        return value
    }
    
    func warmUpAi() async -> Bool {
        let value: HealthLite? = try? await health()
        guard let value else { return false }
        return value.ok
    }
    
    public func health<T: Health>() async throws -> T? {
        let value: T? = await network.send(method: .get, route: .aiHealth)
        return value
    }
}
