//
//  WordProvider.swift
//  WordZap
//
//  Created by Barak Ben Hur on 13/09/2025.
//

import Observation

struct WordProvider {
    let network: Network
    
    init() {
        network = Network(root: .words)
    }
    
    func word(uniqe: String) async -> SimpleWord? {
        let value: SimpleWord? = await network.send(route: .word,
                                                    parameters: ["uniqe": uniqe])
        return value
    }
}
