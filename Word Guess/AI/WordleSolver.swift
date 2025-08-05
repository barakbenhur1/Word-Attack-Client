
import Foundation
import CoreML
import Tokenizers

func generateWord(length: Int) -> String {
    let letters = "abcdefghijklmnopqrstuvwxyz"
    return String((0..<length).map { _ in letters.randomElement()! })
}

enum LetterFeedback: Int, CaseIterable {
    case gray = 0
    case yellow = 1
    case green = 2
}

class WordleSolver {
    private(set) var possibleAnswers: [String]
    private let allAnswers: [String]
    private let allGuesses: [String]
    private var lastGuess: String = ""
    
    init(isHebrew: Bool) {
        let words = Self.loadWordList(from: isHebrew ? "words_he" : "words")
        self.allAnswers = words
        self.allGuesses = words
        self.possibleAnswers = allAnswers
    }
    
    static private func loadWordList(from file: String) -> [String] {
        guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
              let content = try? String(contentsOf: url) else {
            fatalError("Failed to load \(file).txt from bundle.")
        }
        
        return content
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count == 5 }
    }
    
    func bestGuess() -> String {
        guard !possibleAnswers.isEmpty else { return lastGuess.isEmpty ? generateWord(length: 5) : lastGuess }
        
        var letterScores = [Character: Int]()
        for word in possibleAnswers {
            for char in Set(word) {
                letterScores[char, default: 0] += 1
            }
        }
        
        func score(_ word: String) -> Int {
            Set(word).reduce(0) { $0 + (letterScores[$1] ?? 0) }
        }
        
        lastGuess = possibleAnswers.max(by: { score($0) < score($1) }) ?? possibleAnswers.first!
        return lastGuess
    }
    
    func applyFeedback(guess: String, feedback: [LetterFeedback]) {
        possibleAnswers = possibleAnswers.filter { candidate in
            match(guess: guess, feedback: feedback, candidate: candidate)
        }
    }
    
    private func match(guess: String, feedback: [LetterFeedback], candidate: String) -> Bool {
        let candidateChars = Array(candidate)
        let guessChars = Array(guess)
        var used = Array(repeating: false, count: 5)
        
        // First pass – green
        for i in 0..<5 {
            if feedback[i] == .green {
                if candidateChars[i] != guessChars[i] {
                    return false
                }
                used[i] = true
            }
        }
        
        // Second pass – yellow and gray
        for i in 0..<5 {
            let gChar = guessChars[i]
            switch feedback[i] {
            case .yellow:
                if candidateChars[i] == gChar { return false }
                if let idx = candidateChars.enumerated().first(where: { $0.element == gChar && !used[$0.offset] })?.offset {
                    used[idx] = true
                } else {
                    return false
                }
            case .gray:
                let requiredCount = zip(guessChars, feedback).filter { $0.0 == gChar && $0.1 != .gray }.count
                let actualCount = candidateChars.filter { $0 == gChar }.count
                if actualCount > requiredCount {
                    return false
                }
            default: break
            }
        }
        
        return true
    }
}
