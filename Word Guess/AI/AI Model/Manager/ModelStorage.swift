//
//  ModelStorage.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 15/08/2025.
//

import Foundation

enum ModelStorage {
    // If set, use this as the root (e.g. AIPackManager can inject its installRoot)
    private static var overrideRoot: URL?
    
    /// Call this after the GitHub download completes to point ModelStorage at the
    /// exact folder where the models were installed (AIPack/v{version}).
    static func setInstallRoot(_ root: URL) {
        overrideRoot = root
        try? excludeFromBackup(root)
    }
    
    /// Root for persisted models (versioned).
    /// Prefers:  ~/Library/Application Support/AIPack/v{version}
    /// Falls back to: ~/Library/Application Support/Models/v{version}
    static func versionedRoot(version: Int = AIPack.currentVersion) throws -> URL {
        if let r = overrideRoot { return r }
        
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory,
                              in: .userDomainMask,
                              appropriateFor: nil,
                              create: true)
        
        // New location used by the GitHub downloader
        let newRoot = base
            .appendingPathComponent("AIPack", isDirectory: true)
            .appendingPathComponent("v\(version)", isDirectory: true)
        
        // Old location kept for backward compatibility
        let oldRoot = base
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("v\(version)", isDirectory: true)
        
        if fm.fileExists(atPath: newRoot.path) {
            try excludeFromBackup(newRoot)
            return newRoot
        }
        
        if fm.fileExists(atPath: oldRoot.path) {
            try excludeFromBackup(oldRoot)
            return oldRoot
        }
        
        // Neither exists yet → create the new one
        try fm.createDirectory(at: newRoot, withIntermediateDirectories: true)
        try excludeFromBackup(newRoot)
        return newRoot
    }
    
    static func modelDir(name: String, version: Int = AIPack.currentVersion) throws -> URL {
        try versionedRoot(version: version)
            .appendingPathComponent("\(name).mlmodelc", isDirectory: true)
    }
    
    /// Check a single compiled model folder exists locally.
    static func modelExists(_ name: String, version: Int = AIPack.currentVersion) -> Bool {
        guard let url = try? modelDir(name: name, version: version) else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
    
    /// Remove all other version folders under the same parent, keep the given version.
    static func cleanOldVersions(keepVersion: Int) throws {
        let fm = FileManager.default
        let current = try versionedRoot(version: keepVersion)
        let parent = current.deletingLastPathComponent() // .../AIPack or .../Models
        let items = (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
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
    
    static func localHasUsableModels(version: Int = AIPack.currentVersion) -> Bool {
        let hasPrefill   = modelExists("WordleGPT_prefill", version: version)
        let hasDecode    = modelExists("WordleGPT_decode",  version: version)
        let hasFallback  = modelExists("WordleGPT",         version: version)
        return (hasPrefill && hasDecode) || hasFallback
    }
}
