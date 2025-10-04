//
//  ScoreboardData.swift
//  WordZap
//
//  Created by Barak Ben Hur on 15/10/2024.
//

import Foundation

struct Day: Codable, Hashable {
    let value: String
    let difficulties: [Diffculty]
    
    static let empty = Day(value: "", difficulties: [])
}

struct Diffculty: Codable, Hashable {
    let value: String
    let words: [String]
    let members: [Member]
}

struct Member: Codable, Hashable {
    let email: String
    let name: String
    let totalScore: Int
    let words: [FullWord]
}

struct FullWord: Codable, Equatable, Hashable {
    let value: String
    let guesswork: [String]
    let done: Bool
}
