//
//  AppUpdateOverlay.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 03/10/2025.
//

import SwiftUI

// MARK: - App Store version checker (by bundleId)
@Observable
@MainActor
final class AppStoreVersionChecker: ObservableObject {
    struct Result { let latest: String; let url: URL }
    
    private let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    private let bundleId = Bundle.main.bundleIdentifier ?? ""
    
    private var notice: Result? = nil
    private var dismissed: Bool = false
    
    var isDismissed: Bool { dismissed }
    var needUpdate: Result? { notice }
    
    func check(countryCode: String? = Locale.current.region?.identifier) async {
        guard !Self.isTestFlight else { return }
        do {
            let info = try await fetchLatestFromAppStore(country: countryCode ?? "US")
            guard isVersion(current, lessThan: info.latest) && !dismissed else { return }
            notice = info
        } catch { print("silent fail") }
    }
    
    func dismiss() {
        dismissed = true
    }
    
    private func fetchLatestFromAppStore(country: String) async throws -> Result {
        let encoded = bundleId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bundleId
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(encoded)&country=\(country)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Lookup: Decodable { let resultCount: Int; let results: [App] }
        struct App: Decodable { let version: String; let trackViewUrl: String? }
        let decoded = try JSONDecoder().decode(Lookup.self, from: data)
        guard let app = decoded.results.first,
              let urlStr = app.trackViewUrl, let storeURL = URL(string: urlStr) else {
            throw URLError(.badServerResponse)
        }
        return .init(latest: app.version, url: storeURL)
    }
    
    // MARK: - Version parsing & comparison
    
    /// Parses tolerant semver: handles "1.2.3 (123)" and "1.2"
    private func semver(_ s: String) -> [Int] {
        let core = s.split(whereSeparator: { $0 == " " || $0 == "(" }).first.map(String.init) ?? s
        return core.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
    }
    
    /// Lexicographic compare with zero-padding (e.g., 1.2 == 1.2.0)
    private func isVersion(_ a: String, lessThan b: String) -> Bool {
        let va = semver(a), vb = semver(b)
        let n = max(va.count, vb.count)
        for i in 0..<n {
            let x = i < va.count ? va[i] : 0
            let y = i < vb.count ? vb[i] : 0
            if x != y { return x < y }
        }
        return false
    }
    
    private static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
}


// MARK: - Center overlay card (non-blocking outside)
struct UpdateOverlayView: View {
    let latest: String
    let onUpdate: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        ZStack {
            // Transparent, pass-through backdrop (doesn't block taps)
            Color.clear
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            // Floating card (only this area is interactive)
            VStack(spacing: 14) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                
                Text("Update available")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                
                Text("Version \(latest) is available on the App Store.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 10) {
                    Button("Close", action: onClose)
                        .buttonStyle(.bordered)
                    Button("Update", action: onUpdate)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.08))
                    )
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            )
            .padding(34)
            .transition(.scale.combined(with: .opacity))
            .accessibilityAddTraits(.isModal) // visually modal, but not blocking backdrop
        }
        .zIndex(9999) // stay on top
    }
}
