//
//  AdOverlayWindowPresenter.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 24/09/2025.
//

import UIKit
import GoogleMobileAds

// Host VC that forwards status bar control to the presented (ad) VC.
private final class HostAdViewController: UIViewController {
    override var prefersStatusBarHidden: Bool {
        presentedViewController?.prefersStatusBarHidden ?? false
    }
    override var preferredStatusBarStyle: UIStatusBarStyle {
        presentedViewController?.preferredStatusBarStyle ?? .default
    }
    override var childForStatusBarHidden: UIViewController? {
        presentedViewController
    }
    override var childForStatusBarStyle: UIViewController? {
        presentedViewController
    }
}

final class AdOverlayWindowPresenter: NSObject, GADFullScreenContentDelegate {
    static let shared = AdOverlayWindowPresenter()

    private var window: UIWindow?
    private var hostVC: HostAdViewController?
    private var completion: (() -> Void)?

    func present(_ ad: GADInterstitialAd, completion: @escaping () -> Void) {
        self.completion = completion

        // Attach to the active scene to avoid any scene mismatch issues.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first

        let overlay = UIWindow(frame: UIScreen.main.bounds)
        overlay.windowLevel = .alert + 1
        overlay.backgroundColor = .clear
        if let scene { overlay.windowScene = scene }

        let host = HostAdViewController()
        host.view.backgroundColor = .clear
        overlay.rootViewController = host
        overlay.isHidden = false
        overlay.makeKeyAndVisible()

        self.window = overlay
        self.hostVC = host

        ad.fullScreenContentDelegate = self
        // Present the ad; status bar queries will be forwarded to the ad VC.
        ad.present(fromRootViewController: host)
        host.setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - GADFullScreenContentDelegate
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        teardownAndComplete()
    }

    func ad(_ ad: GADFullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        teardownAndComplete()
    }

    private func teardownAndComplete() {
        // Restore status bar control to the app and clean up.
        hostVC?.setNeedsStatusBarAppearanceUpdate()
        window?.isHidden = true
        window = nil
        hostVC = nil
        let done = completion
        completion = nil
        // Call back on the next runloop to let UIKit settle.
        DispatchQueue.main.async { done?() }
    }
}

