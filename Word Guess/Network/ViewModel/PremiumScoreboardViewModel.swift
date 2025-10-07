//
//  PremiumScoreboardViewModel.swift
//  WordZap
//
//  Created by Barak Ben Hur on 13/09/2025.
//

import SwiftUI

@Observable
class PremiumScoreboardViewModel: ObservableObject {
    var data: [PremiumScoreData]?
    
    private let service: PremiumScoreProvider
    
    required init() {
        service = .init()
    }
    
    func items(uniqe: String) async {
        guard !uniqe.isEmpty else { return }
        let value = await service.getAllPremium(uniqe: uniqe)
        guard let value else { return }
        data = value
    }
}
