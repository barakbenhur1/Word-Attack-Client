//
//  LeaderboaredPlaceData.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 30/08/2025.
//

// LeaderboaredPlaceData.swift
// (kept your filename; type is Codable so we can store it easily)

import Foundation

struct LeaderboaredPlaceData: Codable {
    let easy: Int?
    let medium: Int?
    let hard: Int?

    func place(for difficulty: Difficulty) -> Int? {
        switch difficulty {
        case .easy:   return easy
        case .medium: return medium
        case .hard:   return hard
        }
    }
}

