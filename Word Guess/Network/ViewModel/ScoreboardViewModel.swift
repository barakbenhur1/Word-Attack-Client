//
//  ScoreboardViewModel.swift
//  WordZap
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
        network = Network(root: .score)
    }
    
    func items(uniqe: String) async {
        guard !uniqe.isEmpty else { return }
        let value: [Day]? = await network.send(route: .scoreboard,
                                               parameters: ["uniqe": uniqe])
        guard let value else { return }
        data = value
    }
}
