//
//  FileManager+Utils.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 15/08/2025.
//

import Foundation

extension FileManager {
    
    func ensureDirectory(at url: URL, replaceIfExists: Bool = false) throws {
        var isDir: ObjCBool = false
        if fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
            if replaceIfExists { try removeItem(at: url) }
            else {
                throw NSError(domain: "ai.fs", code: 4000,
                              userInfo: [NSLocalizedDescriptionKey: "Path exists and is not a directory: \(url.path)"])
            }
        }
        try createDirectory(at: url, withIntermediateDirectories: true)
    }
    
    /// Backwards-compatible name used in your code.
    func replaceItemAtOrMove(from src: URL, to dst: URL) throws {
        try moveReplacingItem(from: src, to: dst)
    }
    
    /// Best-effort replace: APFS swap → remove+move → copy+remove.
    func moveReplacingItem(from src: URL, to dst: URL) throws {
        guard fileExists(atPath: src.path) else {
            throw NSError(domain: "ai.fs", code: 4001,
                          userInfo: [NSLocalizedDescriptionKey: "Source missing: \(src.lastPathComponent)"])
        }
        try ensureDirectory(at: dst.deletingLastPathComponent())
        
        if fileExists(atPath: dst.path) {
            do {
                _ = try replaceItemAt(dst,
                                      withItemAt: src,
                                      backupItemName: nil,
                                      options: [])
                return
            } catch {
                try? removeItem(at: dst)
            }
        }
        
        do {
            try moveItem(at: src, to: dst)
            return
        } catch {
            try ensureDirectory(at: dst.deletingLastPathComponent())
            do {
                try moveItem(at: src, to: dst)
                return
            } catch {
                try copyItem(at: src, to: dst)
                try? removeItem(at: src)
            }
        }
    }
    
    /// Move every child of `srcDir` into `dstDir`, replacing collisions.
    func replaceDirectoryTree(from srcDir: URL, to dstDir: URL) throws {
        try ensureDirectory(at: dstDir)
        let items = try contentsOfDirectory(
            at: srcDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for src in items {
            let dst = dstDir.appendingPathComponent(src.lastPathComponent, isDirectory: false)
            try moveReplacingItem(from: src, to: dst)
        }
    }
}
