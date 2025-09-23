//
//  InterstitialAdsManager.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 21/10/2024.
//

import Foundation
import GoogleMobileAds
import SwiftUI

@Observable
class InterstitialAdsManager: NSObject, GADFullScreenContentDelegate, ObservableObject {
    
    // Properties
    var interstitialAdLoaded: Bool = false
    private var interstitialAd: GADInterstitialAd?
    
    private let firebaseFlags: FirebaseFlagManager
    private let adUnitID: String
    private var didDismiss: () -> () = {}
    
    private var InterstitialAdInterval: Int { firebaseFlags.remoteConfig.adFrequency }
    
    init(adUnitID: String) {
        self.adUnitID = adUnitID.toKey()
        self.firebaseFlags = FirebaseFlagManager()
        super.init()
    }
    
    func refashRemoteConfig() {
        firebaseFlags.refashRemoteConfig()
    }
    
    func shouldShowiInterstitial(for number: Int) -> Bool {
        return number > 0 && number % firebaseFlags.remoteConfig.adFrequency == 0
    }
    
    // Load InterstitialAd
    func loadInterstitialAd(){
        GADInterstitialAd.load(withAdUnitID: adUnitID, request: GADRequest()) { [weak self] add, error in
            guard let self = self else {return}
            if let error = error {
                print("🔴: \(error.localizedDescription)")
                self.interstitialAdLoaded = false
                return
            }
            print("🟢: Loading succeeded")
            self.interstitialAd = add
            self.interstitialAdLoaded = true
            self.interstitialAd?.fullScreenContentDelegate = self
        }
    }
    
    // Display InterstitialAd
    func displayInterstitialAd(didDismiss: @escaping () -> ()) {
        guard let root = UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .compactMap({$0 as? UIWindowScene})
            .first?.windows
            .filter({$0.isKeyWindow}).first?.rootViewController else { return }
        
        if let ad = interstitialAd {
            self.didDismiss = didDismiss
            ad.present(fromRootViewController: root)
            self.interstitialAdLoaded = false
        }else{
            print("🔵: Ad wasn't ready")
            self.interstitialAdLoaded = false
            self.loadInterstitialAd()
        }
    }
    
    // Failure notification
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("🟡: Failed to display interstitial ad")
        self.loadInterstitialAd()
    }
    
    // Indicate notification
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("🤩: Displayed an interstitial ad")
        self.interstitialAdLoaded = false
    }
    
    // Close notification
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("😔: Interstitial ad closed")
        didDismiss()
    }
}
