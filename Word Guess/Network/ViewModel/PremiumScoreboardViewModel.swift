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
    
    func items(email: String) async {
        guard !email.isEmpty else { return }
        let value = await service.getAllPremium(email: email)
        guard let value else { return }
        data = value
    }
}
