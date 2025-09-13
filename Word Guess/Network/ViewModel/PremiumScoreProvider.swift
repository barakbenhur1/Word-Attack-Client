//
//  PremiumScoreProvider.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 13/09/2025.
//

import Foundation

struct PremiumScoreProvider {
    let network: Network
    
    init() {
        network = Network(root: "score")
    }
    
    func getPremium(email: String) async -> PremiumScoreData? {
        let value: PremiumScoreData? = await network.send(route: "getPremiumScore",
                                                          parameters: ["email": email])
        
        let wins = value
        return wins
    }
}
