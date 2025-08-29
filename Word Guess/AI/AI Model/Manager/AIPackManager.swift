//
//  AIPackManager.swift
//  Word Guess
//  Created by Barak Ben Hur on 15/08/2025.
//

import Foundation

enum AIPack {
    static let currentVersion = 1                            // bump when shipping new AI
    static let currentTag = "ai-pack-v\(currentVersion)"     // match File Inspector tag
    static let defaultsKey = "AIPackVersion"
}

@Observable
final class AIPackManager {
    private let odr = ODRDownloader()

    var isReady: Bool { odr.isReady }
    var progress: Double { odr.progress }
    var errorText: String? { odr.errorText }
    var completedBytes: Int64 { odr.completedBytes }
    var totalBytes: Int64 { odr.totalBytes }

    func ensurePackReady(priority: Double = 1.0, preserve: Double = 0.95) {
        odr.fetch(tag: AIPack.currentTag, priority: priority, preserve: preserve)
    }

    func releaseLease() { odr.endAccessing() }

    /// Call on app launch (or before first use) to migrate versions and clean old local copies.
    func migrateIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: AIPack.defaultsKey)
        guard stored != AIPack.currentVersion else { return }

        if stored > 0 {
            let oldTag = "ai-pack-v\(stored)"
            Bundle.main.setPreservationPriority(0.0, forTags: [oldTag])
        }
        Bundle.main.setPreservationPriority(0.95, forTags: [AIPack.currentTag])
        UserDefaults.standard.set(AIPack.currentVersion, forKey: AIPack.defaultsKey)

        // Optional: clear older local versions
        try? ModelStorage.cleanOldVersions(keepVersion: AIPack.currentVersion)
    }
}
