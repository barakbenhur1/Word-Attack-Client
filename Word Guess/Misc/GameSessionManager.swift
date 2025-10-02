//
//  GameSessionManager.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 30/09/2025.
//

import Foundation

final class GameSessionManager: ObservableObject {
    // Track whether a round is in progress and the current round ID
    @Published private(set) var activeGameID: String?
    
    func startNewRound(id: DifficultyType) {
        activeGameID = id.rawValue
    }
    
    func finishRound() {
        activeGameID = nil
    }
    
    var hasActiveRound: Bool { activeGameID != nil }
}
