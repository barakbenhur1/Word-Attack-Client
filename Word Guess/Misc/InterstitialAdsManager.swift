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
    var isPresenting: Bool = false
    var interstitialAdLoaded: Bool = false { didSet { isPresenting = interstitialAdLoaded } }
    var initialInterstitialAdLoaded: Bool = false { didSet { isPresenting = initialInterstitialAdLoaded } }
    private var initialInterstitialAd: GADInterstitialAd?
    private var interstitialAd: GADInterstitialAd?
    
    private let firebaseFlags: FirebaseFlagManager
    private let adUnitID: String
    private var didDismissInitial: () -> () = {}
    private var didDismiss: () -> () = {}
    
    init(adUnitID: String) {
        self.adUnitID = adUnitID.toKey()
        self.firebaseFlags = FirebaseFlagManager()
        super.init()
    }
    
    func refashRemoteConfig() {
        firebaseFlags.refashRemoteConfig()
    }
    
    func shouldShowInterstitial(for number: Int) -> Bool {
        return number > 0 && number % firebaseFlags.remoteConfig.adFrequency == 0
    }
    
    func loadInitialInterstitialAd(){
        GADInterstitialAd.load(withAdUnitID: adUnitID, request: GADRequest()) { [weak self] add, error in
            guard let self = self else { return }
            self.initialInterstitialAdLoaded = true
            if let error = error {
                print("🔴: \(error.localizedDescription)")
                didDismissInitial()
                return
            }
            print("🟢: Loading succeeded")
            self.initialInterstitialAd = add
            self.initialInterstitialAd?.fullScreenContentDelegate = self
            guard initialInterstitialAd != nil else { didDismissInitial(); return }
            displayInitialInterstitialAd(didDismiss: didDismissInitial)
        }
    }
    
    // Load InterstitialAd
    func loadInterstitialAd(){
        GADInterstitialAd.load(withAdUnitID: adUnitID, request: GADRequest()) { [weak self] add, error in
            guard let self = self else { return }
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
    func displayInitialInterstitialAd(didDismiss: @escaping () -> ()) {
        guard let root = UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .compactMap({$0 as? UIWindowScene})
            .first?.windows
            .filter({$0.isKeyWindow}).first?.rootViewController else { return }
        
        self.didDismissInitial = didDismiss
       
        if let ad = initialInterstitialAd {
            self.initialInterstitialAdLoaded = true
            ad.present(fromRootViewController: root)
        } else {
            print("🔵: Ad wasn't ready")
            self.initialInterstitialAdLoaded = false
            self.loadInitialInterstitialAd()
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
        } else {
            print("🔵: Ad wasn't ready")
            self.interstitialAdLoaded = false
            self.loadInterstitialAd()
        }
    }
    
    // Failure notification
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("🟡: Failed to display interstitial ad")
        if interstitialAdLoaded {
            interstitialAdLoaded = false
            self.loadInterstitialAd()
        } else { loadInitialInterstitialAd() }
    }
    
    // Indicate notification
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("🤩: Displayed an interstitial ad")
    }
    
    // Close notification
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("😔: Interstitial ad closed")
        if interstitialAdLoaded {
            didDismiss()
            interstitialAdLoaded = false
        } else { didDismissInitial() }
    }
}
