//
//  ScoreboardViewModel.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 15/10/2024.
//

import SwiftUI

@Observable
class ScoreboardViewModel: ObservableObject {
    var data: [Day] = []
    private let queue = DispatchQueue.main
    
    private let network: Network
    
    required init() {
        network = Network(root: "words")
    }
    
    func items(email: String) async {
        let value: [Day]? = await network.send(route: "scoreboard",
                                               parameters: ["email": email])
        guard let value else { return }
        data = value
    }
}
