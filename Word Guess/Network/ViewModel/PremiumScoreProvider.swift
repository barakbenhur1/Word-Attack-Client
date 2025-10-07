//
//  PremiumScoreProvider.swift
//  WordZap
//
//  Created by Barak Ben Hur on 13/09/2025.
//

import Foundation

struct PremiumScoreProvider {
    let network: Network
    
    init() {
        network = Network(root: .score)
    }
    
    func getPremium(uniqe: String) async -> PremiumScoreData? {
        let value: PremiumScoreData? = await network.send(route: .getPremiumScore,
                                                          parameters: ["uniqe": uniqe])
        return value
    }
    
    
    func getAllPremium(uniqe: String) async -> [PremiumScoreData]? {
        let value: [PremiumScoreData]? = await network.send(route: .getAllPremiumScores,
                                                          parameters: ["uniqe": uniqe])
        return value
    }
}
