//
//  AIHealthCheck.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 15/08/2025.
//

// AIHealthCheck.swift
import Foundation
#if canImport(CoreML)
import CoreML
#endif

enum AIHealthCheck {
    static func run(note: String = "") {
        print("🔎 AIHealthCheck START \(note.isEmpty ? "" : "[\(note)]")")
        print("AIPack.version=\(AIPack.currentVersion)  tag=\(AIPack.currentTag)")

        // Local root
        let root = try? ModelStorage.versionedRoot()
        print("Local root: \(root?.path ?? "nil")")

        // Local presence
        func local(_ name: String) -> Bool { ModelStorage.modelExists(name) }
        let hasPre = local("WordleGPT_prefill")
        let hasDec = local("WordleGPT_decode")
        let hasFb  = local("WordleGPT")
        print("Local models  → prefill:\(hasPre) decode:\(hasDec) fallback:\(hasFb)")

        // Bundle/ODR presence
        func bundle(_ name: String) -> Bool {
            Bundle.main.url(forResource: name, withExtension: "mlmodelc") != nil
        }
        print("Bundle/ODR    → prefill:\(bundle("WordleGPT_prefill")) decode:\(bundle("WordleGPT_decode")) fallback:\(bundle("WordleGPT"))")

        // Resolved URLs (local-first)
        let pURL = WordleAI.findOptionalModelURL(named: "WordleGPT_prefill")
        let dURL = WordleAI.findOptionalModelURL(named: "WordleGPT_decode")
        let fURL = WordleAI.findOptionalModelURL(named: "WordleGPT")
        print("Resolved URLs → p:\(pURL?.path ?? "nil")  d:\(dURL?.path ?? "nil")  f:\(fURL?.path ?? "nil")")

        // Sidecars (local root)
        if let root {
            let side = [
                "tokenizer.json","tokenizer","tokenizer_config.json","special_tokens_map.json",
                "tokenizer.model","config.json","WordleGPT_runtime_spec","WordleGPT_runtime_spec.json"
            ]
            for s in side {
                let u = root.appendingPathComponent(s)
                if FileManager.default.fileExists(atPath: u.path) {
                    print("Sidecar (local) OK: \(s)")
                }
            }
        }

        // Try a real load to prove the path works
        #if canImport(CoreML)
        do {
            if let u = pURL ?? dURL ?? fURL {
                _ = try MLModel(contentsOf: u)
                print("✅ Model LOAD OK from: \(u.lastPathComponent)")
            } else {
                print("❌ No model URL to load.")
            }
        } catch {
            print("❌ Model LOAD ERROR: \(error)")
        }
        #endif

        print("🔎 AIHealthCheck END")
    }
}
