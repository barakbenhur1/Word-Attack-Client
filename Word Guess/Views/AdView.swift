//
//  AdView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 21/10/2024.
//

import GoogleMobileAds
import SwiftUI
import AppTrackingTransparency

struct AdView: View {
    let adUnitID: String
    var body: some View {
        BannerView(adUnitID: adUnitID)
            .frame(width: GADAdSizeBanner.size.width,
                   height: GADAdSizeBanner.size.height)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in ATTrackingManager.requestTrackingAuthorization(completionHandler: { status in }) }
    }
}


struct BannerView: UIViewControllerRepresentable {
    
    private let adUnitID: String
    
    private let bannerView = GADBannerView(adSize: GADAdSizeBanner)
    
    init(adUnitID: String) {
        self.adUnitID = adUnitID.toKey()
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = viewController
        viewController.view.addSubview(bannerView)
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        bannerView.load(GADRequest())
    }
}
