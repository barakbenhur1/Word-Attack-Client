//
//  InterstitialAdsManager.swift
//  WordZap
//
//  Created by Barak Ben Hur on 21/10/2024.
//

import Foundation
import GoogleMobileAds
import SwiftUI

@Observable
class InterstitialAdsManager: NSObject, GADFullScreenContentDelegate, ObservableObject {
    
    // MARK: - Cooldown (90s global)
    private let minAdInterval: TimeInterval = 90
    private let lastAdShownKey = "InterstitialAdsManager.lastAdShownAt"
    
    /// Backed by UserDefaults so it survives new manager instances / app relaunch.
    private var lastAdShownAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: lastAdShownKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastAdShownKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastAdShownKey)
            }
        }
    }
    
    private func canShowAnotherAd() -> Bool {
        guard let last = lastAdShownAt else { return true }
        return Date().timeIntervalSince(last) >= minAdInterval
    }
    
    // MARK: - Properties
    var isPresenting: Bool = false
    var interstitialAdLoaded: Bool = false { didSet { isPresenting = interstitialAdLoaded } }
    var initialInterstitialAdLoaded: Bool = false { didSet { isPresenting = initialInterstitialAdLoaded } }
    
    private var initialInterstitialAd: GADInterstitialAd?
    private var interstitialAd: GADInterstitialAd?
    
    private let firebaseFlags: FirebaseFlagManager
    private let adUnitID: String
    private var didDismissInitial: () -> () = {}
    private var didDismiss: () -> () = {}
    
    // MARK: - Init
    
    init(adUnitID: String) {
        self.adUnitID = adUnitID.toKey()
        self.firebaseFlags = FirebaseFlagManager()
        super.init()
    }
    
    func refashRemoteConfig() {
        firebaseFlags.refashRemoteConfig()
    }
    
    /// Frequency + cooldown in one place.
    func shouldShowInterstitial(for number: Int) -> Bool {
        guard number > 0,
              number % firebaseFlags.remoteConfig.adFrequency == 0 else {
            return false
        }
        return canShowAnotherAd()
    }
    
    // MARK: - Load
    
    func loadInitialInterstitialAd() {
        GADInterstitialAd.load(withAdUnitID: adUnitID, request: GADRequest()) { [weak self] add, error in
            guard let self else { return }
            self.initialInterstitialAdLoaded = true
            
            if let error {
                print("🔴 initial load error: \(error.localizedDescription)")
                self.didDismissInitial()
                return
            }
            
            print("🟢 initial interstitial loaded")
            self.initialInterstitialAd = add
            self.initialInterstitialAd?.fullScreenContentDelegate = self
            guard self.initialInterstitialAd != nil else {
                self.didDismissInitial()
                return
            }
            self.displayInitialInterstitialAd(didDismiss: self.didDismissInitial)
        }
    }
    
    func loadInterstitialAd() {
        GADInterstitialAd.load(withAdUnitID: adUnitID, request: GADRequest()) { [weak self] add, error in
            guard let self else { return }
            if let error {
                print("🔴 load error: \(error.localizedDescription)")
                self.interstitialAdLoaded = false
                return
            }
            print("🟢 interstitial loaded")
            self.interstitialAd = add
            self.interstitialAdLoaded = true
            self.interstitialAd?.fullScreenContentDelegate = self
        }
    }
    
    // MARK: - Display
    
    func displayInitialInterstitialAd(didDismiss: @escaping () -> () = {}) {
        guard let root = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .first(where: { $0.isKeyWindow })?.rootViewController else { return }
        
        self.didDismissInitial = didDismiss
        
        // 60s cooldown
        guard canShowAnotherAd() else {
            print("⏱️ Skipping INITIAL interstitial – cooldown active")
            DispatchQueue.main.async {
                didDismiss()
            }
            return
        }
        
        if let ad = initialInterstitialAd {
            initialInterstitialAdLoaded = true
            ad.present(fromRootViewController: root)
        } else {
            print("🔵 initial ad not ready")
            initialInterstitialAdLoaded = false
            loadInitialInterstitialAd()
        }
    }
    
    func displayInterstitialAd(didDismiss: @escaping () -> ()) {
        guard let root = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .first(where: { $0.isKeyWindow })?.rootViewController else { return }
        
        self.didDismiss = didDismiss
        
        // 60s cooldown
        guard canShowAnotherAd() else {
            print("⏱️ Skipping interstitial – cooldown active")
            DispatchQueue.main.async {
                didDismiss()
            }
            return
        }
        
        if let ad = interstitialAd {
            ad.present(fromRootViewController: root)
        } else {
            print("🔵 interstitial not ready")
            interstitialAdLoaded = false
            loadInterstitialAd()
            // No ad actually shown, continue flow
            DispatchQueue.main.async {
                didDismiss()
            }
        }
    }
    
    // MARK: - GADFullScreenContentDelegate
    
    func ad(_ ad: GADFullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        print("🟡 failed to present interstitial: \(error.localizedDescription)")
        if interstitialAdLoaded {
            interstitialAdLoaded = false
            loadInterstitialAd()
        } else {
            loadInitialInterstitialAd()
        }
    }
    
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        print("🤩 presenting interstitial")
    }
    
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        // Mark the moment an ad is actually shown – start cooldown.
        print("😔 interstitial dismissed")
        lastAdShownAt = Date()
        if interstitialAdLoaded {
            interstitialAdLoaded = false
            didDismiss()
        } else {
            didDismissInitial()
        }
    }
}
