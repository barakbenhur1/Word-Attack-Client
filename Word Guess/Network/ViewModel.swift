//
//  VM.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 17/08/2025.
//

import Foundation

@Observable
class ViewModel: ObservableObject {
    var wordValue: String { return "" }
    
    internal func calculateColors(with guess: [String], length: Int) -> [CharColor] {
        var colors = [CharColor](repeating: .noMatch,
                                 count: length)
        
        var containd = [String: Int]()
        
        for char in wordValue.lowercased() {
            let key = String(char).returnChar(isFinal: false)
            if containd[key] == nil { containd[key] = 1 }
            else { containd[key]! += 1 }
        }
        
        for i in 0..<guess.count {
            if guess[i].lowercased().isEquel(wordValue[i].lowercased()) {
                containd[guess[i].lowercased().returnChar(isFinal: false)]! -= 1
                colors[i] = .exactMatch
            }
        }
        
        for i in 0..<guess.count {
            guard !guess[i].lowercased().isEquel(wordValue[i].lowercased()) else { continue }
            if wordValue.lowercased().toSuffixChars().contains(guess[i].lowercased().returnChar(isFinal: true)) && containd[guess[i].lowercased().returnChar(isFinal: false)]! > 0 {
                containd[guess[i].lowercased().returnChar(isFinal: false)]! -= 1
                colors[i] = .partialMatch
            } else { colors[i] = .noMatch }
        }
        
        return colors
    }
}
