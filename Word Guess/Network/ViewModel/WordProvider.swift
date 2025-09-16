//
//  WordProvider.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 13/09/2025.
//

import Observation

struct WordProvider {
    let network: Network
    
    init() {
        network = Network(root: .words)
    }
    
    func word(email: String) async -> SimpleWord? {
        let value: SimpleWord? = await network.send(route: .word,
                                                    parameters: ["email": email])
        return value
    }
}
