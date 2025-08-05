//
//  WordleViewModel.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 04/08/2025.
//

import SwiftUI

typealias GuessHistoryItem = (guess: String, feedback: [LetterFeedback])

@MainActor
class WordleViewModel: ObservableObject {
    private let solver: WordleSolver
    
    init(isHebrew: Bool) {
        solver = WordleSolver(isHebrew: isHebrew)
    }
    
    func reset() {
        solver.reset()
    }
    
    func submitFeedback(prv: GuessHistoryItem = ("     ", Array(repeating: .gray, count: 5))) -> String {
        solver.applyFeedback(guess: prv.guess, feedback: prv.feedback)
        return solver.bestGuess()
    }
}
