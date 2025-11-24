//
//  AppUpdateOverlay.swift
//  WordZap
//
//  Created by Barak Ben Hur on 03/10/2025.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class AppStoreVersionChecker: ObservableObject {
    struct Result { let latest: String; let url: URL }
    
    // === original dismiss model (in-memory only) ===
    private var dismissed: Bool
    var isDismissed: Bool {
        // Ensure views track changes to the stored property
        access(keyPath: \.dismissed)
        return dismissed
    }
    
    init() { dismissed = false }
    
    // MARK: - Current app version (robust)
    private var current: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return v }
        if let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           b.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return b }
        return "0.0.0"
    }

    private let bundleId = Bundle.main.bundleIdentifier ?? ""
    private var notice: Result? = nil

    var needUpdate: Result? {
        // Ensure views track changes to the stored property
        access(keyPath: \.notice)
        return notice
    }
    
    func check(countryCode: String? = Locale.current.region?.identifier) async {
        guard !Self.isTestFlight, !Self.isExtension, !Self.isPreview, !dismissed else { return }
        
        // If we still can’t parse anything sensible, don’t nag.
        let cur = normalize(current)
        guard cur != [0] else { return }
        
        // Prefer device storefront; fall back to US if needed (no async-in-autoclosure).
        let cc = (countryCode?.uppercased().prefix(2)).map(String.init) ?? "US"
        
        var info: Result?
        if let r = try? await fetchLatestFromAppStore(country: cc) {
            info = r
        } else if cc != "US", let r2 = try? await fetchLatestFromAppStore(country: "US") {
            info = r2
        }
        guard let info else { return }
        
        let latestParts = normalize(info.latest)
        guard isLess(cur, latestParts) else { dismissed = true; return }
        
        notice = info
    }
    
    func dismiss() {
        dismissed = true
    }

    // MARK: - Networking
    private func fetchLatestFromAppStore(country: String) async throws -> Result {
        guard !bundleId.isEmpty else { throw URLError(.badURL) }
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

    // MARK: - Version normalization & compare
    private func normalize(_ s: String) -> [Int] {
        // keep only the core (before space/paren), then split on '.'
        let core = s.split(whereSeparator: { $0 == " " || $0 == "(" }).first.map(String.init) ?? s
        let parts = core.split(separator: ".").map { seg -> Int in
            let digits = seg.filter(\.isNumber)
            return Int(digits) ?? 0
        }
        var arr = parts.isEmpty ? [0] : parts
        while arr.count > 1, arr.last == 0 { arr.removeLast() } // trim trailing zeros
        return arr
    }

    private func isLess(_ a: [Int], _ b: [Int]) -> Bool {
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    // MARK: - Envs
    private static var isTestFlight: Bool {
        // On App Store the receipt filename is "receipt", on TestFlight it's "sandboxReceipt".
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
    private static var isExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
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
            .transition(.scale(1).combined(with: .opacity))
            .accessibilityAddTraits(.isModal) // visually modal, but not blocking backdrop
        }
        .zIndex(9999) // stay on top
    }
}
