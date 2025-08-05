//
//  WordDat.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 14/10/2024.
//

import Foundation

struct WordData: Codable, Equatable, Hashable {
    var score: Int
    let word: Word
    var number: Int
    var isTimeAttack: Bool
    
    static let emapty = WordData(score: 0, word: .init(value: "", guesswork: []), number: 0, isTimeAttack: false)
}


struct Word: Codable, Equatable, Hashable {
    let value: String
    let guesswork: [String]
}


struct WordForAiMode: Codable, Equatable, Hashable {
    let value: String
}
