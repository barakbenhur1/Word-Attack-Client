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
    
    @ViewBuilder func adView(id: String, withPlaceholder: Bool = false) -> some View {
        if !premium.isPremium {
            if withPlaceholder {
                ZStack(alignment: .center) {
                    Rectangle()
                    AdView(adUnitID: id)
                }
            } else { AdView(adUnitID: id) }
        }
        else if withPlaceholder {
            ZStack(alignment: .center) {
                Rectangle()
            }
        }
    }
    
    func interstitialAdsManager(id: String) -> InterstitialAdsManager?  {
        return premium.isPremium ? nil : InterstitialAdsManager(adUnitID: id)
    }
}
