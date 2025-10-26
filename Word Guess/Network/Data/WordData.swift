//
//  WordDat.swift
//  WordZap
//
//  Created by Barak Ben Hur on 14/10/2024.
//

import Foundation

struct WordData: Codable, Equatable, Hashable {
    let word: Word
    var number: Int
    var isTimeAttack: Bool
    
    static let empty = WordData(word: .init(value: "", guesswork: []), number: 0, isTimeAttack: false)
}

struct Word: Codable, Equatable, Hashable {
    let value: String
    let guesswork: [String]
}

struct SimpleWord: Codable, Equatable, Hashable {
    let value: String
    
    static let empty = SimpleWord(value: "")
}

struct ScoreData: Codable, Equatable, Hashable {
    var score: Int
}

struct AiWord: Codable, Equatable, Hashable {
    let guess: String
    let mode: String
}

struct AIHealth: Codable {
    let ok: Bool
    let backend: String?
    let vocabSize: Int?
    let lettersEN: Int?
    let lettersHE: Int?
    let wordsEN: Int?
    let wordsHE: Int?
    let modelPath: String?
    let tokenizerPath: String?
}

enum WarmupStatus {
    case ready(AIHealth)
    case notReady(String?)    // server answered but not ready
}

