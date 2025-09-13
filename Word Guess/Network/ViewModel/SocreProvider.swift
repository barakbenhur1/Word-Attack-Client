//
//  SocrePlaceProvider.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 01/09/2025.
//

import Foundation

struct ScoreProvider {
    let network: Network
    
    init() {
        network = Network(root: "score")
    }
    
    func getPlaceInLeaderboard(email: String) async -> LeaderboaredPlaceData? {
        let value: LeaderboaredPlaceData? = await network.send(route: "place",
                                                               parameters: ["email": email])
        return value
    }
}
