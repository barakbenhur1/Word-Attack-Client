//
//  AdProvider.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 11/09/2025.
//

import SwiftUI

private struct InterstitialAdsManagerConfig {
    let interstitialAdsManager: InterstitialAdsManager
    let id: String
}

@MainActor
class AdProvider: ObservableObject {
    let premium: PremiumManager
    
    private static var interstitialAdsConfig: InterstitialAdsManagerConfig?
    
    init() {
        self.premium = PremiumManager.shared
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
    
    static func interstitialAdsManager(id: String) -> InterstitialAdsManager?  {
        guard !PremiumManager.shared.isPremium else { return nil }
        if let interstitialAdsConfig, id == interstitialAdsConfig.id {
            interstitialAdsConfig.interstitialAdsManager.refashRemoteConfig()
            return interstitialAdsConfig.interstitialAdsManager
        } else {
            let built: InterstitialAdsManagerConfig = .init(interstitialAdsManager: .init(adUnitID: id), id: id)
            built.interstitialAdsManager.refashRemoteConfig()
            interstitialAdsConfig = built
            return built.interstitialAdsManager
        }
    }
}
