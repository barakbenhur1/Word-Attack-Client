//
//  AdView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 21/10/2024.
//

import SwiftUI
import GoogleMobileAds
import UIKit
import AppTrackingTransparency

struct AdView: View {
    let adUnitID: String
    var body: some View {
        AdMobAdaptiveBanner(adUnitID: adUnitID)
            .frame(height: GADAdSizeBanner.size.height)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                    ATTrackingManager.requestTrackingAuthorization { _ in }
                }
            }
    }
}

//private let debugTestBannerID = "ca-app-pub-3940256099942544/2934735716"

public struct AdMobAdaptiveBanner: UIViewControllerRepresentable {
    public typealias UIViewControllerType = BannerViewController
    
    private let adUnitID: String
    private let backgroundColor: UIColor?
    
    /// - Parameters:
    ///   - adUnitID: Banner ID.
    ///   - backgroundColor: Optional background (often .clear).
    public init(adUnitID: String, backgroundColor: UIColor? = nil) {
        self.adUnitID = adUnitID.toKey()
        self.backgroundColor = backgroundColor
    }
    
    public func makeUIViewController(context: Context) -> BannerViewController {
        let vc = BannerViewController(adUnitID: adUnitID, backgroundColor: backgroundColor)
        return vc
    }
    
    public func updateUIViewController(_ uiViewController: BannerViewController, context: Context) {
        // Update size on width changes from SwiftUI.
        uiViewController.updateAdSize(to: uiViewController.view.bounds.width)
    }
}

/// A tiny UIViewController host that manages GADBannerView properly.
public final class BannerViewController: UIViewController {
    private let adUnitID: String
    private var bannerView: GADBannerView?
    private let bgColor: UIColor?
    
    init(adUnitID: String, backgroundColor: UIColor?) {
        self.adUnitID = adUnitID
        self.bgColor = backgroundColor
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bgColor ?? .clear
        setupBanner(forWidth: view.bounds.width)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Keep banner sized to current width (handles rotation/splits).
        updateAdSize(to: view.bounds.width)
    }
    
    public func updateAdSize(to width: CGFloat) {
        guard let bannerView = bannerView else { return }
        let size = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(max(width, 320))
        bannerView.adSize = size
    }
    
    private func setupBanner(forWidth width: CGFloat) {
        let banner = GADBannerView(adSize: GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(max(width, 320)))
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.adUnitID = adUnitID
        banner.rootViewController = self
        
        view.addSubview(banner)
        
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Load the ad
        banner.load(GADRequest())
        self.bannerView = banner
    }
}
