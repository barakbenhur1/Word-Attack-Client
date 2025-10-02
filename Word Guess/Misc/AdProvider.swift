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
    private static var interstitialAdsConfig: InterstitialAdsManagerConfig?
    
    @ViewBuilder static func adView(id: String,
                                    withPlaceholder: Bool = false) -> some View {
        ZStack(alignment: .center) {
            if withPlaceholder {
                Rectangle()
            }
            if !PremiumManager.shared.isPremium {
                AdView(adUnitID: id)
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
