//
//  AIProvider.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 26/10/2025.
//

import Observation
import Foundation

struct AIProvider {
    let network: Network
    
    init() {
        network = Network(root: .ai)
    }
    
    private struct AIGuessRequest: Codable {
        let lang: String       // "en" | "he"
        let difficulty: String // "easy" | "medium" | "hard" | "boss"
        let history: [GuessRow]
    }

    private func makeAIGuessBody(
        lang: String,
        difficulty: String,
        history: [GuessRow]
    ) throws -> Data {
        let req  = AIGuessRequest(lang: lang, difficulty: difficulty, history: history)
        let enc  = JSONEncoder()
        return try enc.encode(req)
    }
    
    
    func aiWord(history: [GuessHistory], lang: Language , difficulty: AIDifficulty) async -> AiWord? {
        guard let parameters = try? makeAIGuessBody(lang: lang.rawValue,
                                                    difficulty: difficulty.stringValue,
                                                    history: history.jsonValid) else { return nil }
        
        let value: AiWord? = await network.send(route: .aiGuess,
                                                parameters: parameters)
        return value
    }
    
    func warmUpAi() async -> Bool {
        let value = try? await waitForAIReady()
        guard let value else { return false }
        
        switch value {
        case .ready(let aIHealth):
            return aIHealth.ok
        case .notReady(let string):
            print(string ?? "unknowen")
            return false
        }
    }
    
    private func waitForAIReady(
        overallTimeout: TimeInterval = 90,
        initialBackoff: TimeInterval = 0.75
    ) async throws -> WarmupStatus {
        let baseURL: URL = URL(string: network.baseURL)!
        let healthURL = baseURL.appendingPathComponent("/ai/aiHealth")
        let deadline = Date().addingTimeInterval(overallTimeout)
        var backoff = initialBackoff

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        while true {
            var req = URLRequest(url: healthURL)
            req.timeoutInterval = 10
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    if let health = try? decoder.decode(AIHealth.self, from: data),
                       health.ok == true,
                       (health.wordsEN ?? 0) > 0 || (health.wordsHE ?? 0) > 0 {
                        return .ready(health) // ✅ warmed
                    } else {
                        if Date() > deadline { return .notReady("health ok=false or empty vocab") }
                    }
                } else {
                    if Date() > deadline { return .notReady("non-200") }
                }
            } catch {
                if Date() > deadline { return .notReady(error.localizedDescription) }
            }

            // exponential backoff with a little jitter
            try await Task.sleep(nanoseconds: UInt64((backoff + Double.random(in: 0...0.25)) * 1_000_000_000))
            backoff = min(backoff * 1.8, 6.0)
        }
    }
}
