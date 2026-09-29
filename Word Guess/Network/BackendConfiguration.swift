//
//  BackendConfiguration.swift
//  WordZap
//
//  Central production backend selection. Render stays the default until the
//  Cloudflare acceptance gate passes; cutover is one configuration change.
//

import Foundation

enum BackendConfiguration {
    static let legacyRenderBaseURL = URL(string: "https://word-attack-server.onrender.com")!

    /// Optional Info.plist override used for a staged Cloudflare build.
    /// Leave absent in the current production build until acceptance passes.
    static var apiBaseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "WORDZAP_API_BASE_URL") as? String,
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return url
        }
        return legacyRenderBaseURL
    }

    static var apiBaseString: String {
        apiBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Cloudflare PVP uses a native WebSocket protocol rather than Socket.IO.
    /// The transport flips automatically only when the configured API host is
    /// a workers.dev deployment (or when explicitly overridden for testing).
    static var usesNativePVP: Bool {
        if let forced = Bundle.main.object(forInfoDictionaryKey: "WORDZAP_NATIVE_PVP") as? Bool {
            return forced
        }
        return apiBaseURL.host?.hasSuffix(".workers.dev") == true
    }

    static var pvpWebSocketURL: URL? {
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.path = "/pvp/socket"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
