//
//  AdProvider.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 11/09/2025.
//

import SwiftUI

@MainActor
class AdProvider: ObservableObject {
    let premium: PremiumManager
    
    init(premium: PremiumManager) {
        self.premium = premium
    }

    @ViewBuilder func adView(id: String) -> some View {
        if !premium.isPremium {
            AdView(adUnitID: id)
        }
    }
    
    func interstitialAdsManager(id: String) -> InterstitialAdsManager?  {
        return premium.isPremium ? nil : InterstitialAdsManager(adUnitID: id)
    }
}
