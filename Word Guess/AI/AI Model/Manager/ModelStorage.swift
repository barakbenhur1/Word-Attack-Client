//
//  ModelStorage.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 15/08/2025.
//

import Foundation

enum ModelStorage {
    /// Root for persisted models (versioned).
    static func versionedRoot(version: Int = AIPack.currentVersion) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = base.appendingPathComponent("Models/v\(version)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try excludeFromBackup(dir)
        return dir
    }

    static func modelDir(name: String, version: Int = AIPack.currentVersion) throws -> URL {
        try versionedRoot(version: version).appendingPathComponent("\(name).mlmodelc", isDirectory: true)
    }

    /// Check a single compiled model folder exists locally.
    static func modelExists(_ name: String, version: Int = AIPack.currentVersion) -> Bool {
        guard let url = try? modelDir(name: name, version: version) else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func cleanOldVersions(keepVersion: Int) throws {
        let fm = FileManager.default
        let modelsRoot = try versionedRoot(version: keepVersion).deletingLastPathComponent() // .../Models/
        let items = (try? fm.contentsOfDirectory(at: modelsRoot, includingPropertiesForKeys: nil)) ?? []
        for url in items where url.lastPathComponent != "v\(keepVersion)" {
            try? fm.removeItem(at: url)
        }
    }

    static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
    }
    
    static func localHasUsableModels() -> Bool {
        let hasPrefill = modelExists("WordleGPT_prefill")
        let hasDecode = modelExists("WordleGPT_decode")
        let hasFallback = modelExists("WordleGPT")
        return (hasPrefill && hasDecode) || hasFallback
    }
}
