//
//  AIPackManager.swift
//  WordZap
//  Created by Barak Ben Hur on 15/08/2025.
//  Uses GitHub Release tag instead of ODR.
//

import Foundation

enum AIPack {
    static let currentVersion = 1
    static let ghOwner = "barakbenhur1"
    static let ghRepo  = "Word-Attack-Client"
    static let ghTag   = "ML_Models"
    static var ghToken: String? { nil }
    static let expectedAssets: [String] = [
        "WordZapGPT_prefill.mlmodelc.zip",
        "WordZapGPT_decode.mlmodelc.zip",
        "tokenizer.model",
        "tokenizer.json",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "config.json",
        "WordZapGPT_runtime_spec.json"
    ]
    static let defaultsKey = "AIPackVersion"
}

@MainActor
@Observable
final class AIPackManager {
    private let dl = GitReleaseDownloader()

    var isReady: Bool { dl.isReady }
    var progress: Double { dl.progress }
    var errorText: String? { dl.errorText }
    var completedBytes: Int64 { dl.completedBytes }
    var totalBytes: Int64 { dl.totalBytes }
    var progressExtra: String? { dl.progressExtra }
    var installRoot: URL? { dl.installedRoot }

    func ensurePackReady() {
        dl.fetch(
            owner: AIPack.ghOwner,
            repo: AIPack.ghRepo,
            tag: AIPack.ghTag,
            version: AIPack.currentVersion,
            expectedAssetNames: AIPack.expectedAssets,
            personalAccessToken: AIPack.ghToken
        )
    }

    func cancel() {
        dl.cancel()
        Task { await dl.shutdown() }
    }

    func migrateIfNeeded() {
        let ud = UserDefaults.standard
        let stored = ud.integer(forKey: AIPack.defaultsKey)
        guard stored != AIPack.currentVersion else { return }
        ud.set(AIPack.currentVersion, forKey: AIPack.defaultsKey)

        let fm = FileManager.default
        if let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                  appropriateFor: nil, create: true)
            .appendingPathComponent("AIPack", isDirectory: true),
           let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles]) {
            for u in items where u.lastPathComponent != "v\(AIPack.currentVersion)" {
                try? fm.removeItem(at: u)
            }
        }
    }
}
