//
//  ModelPostProcessor.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 15/09/2025.
//

import Foundation
import Darwin

enum ModelPostProcessor {
    static func hardenExtractedModelDir(_ dir: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "ModelPostProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a directory: \(dir.path)"])
        }
        var urls: [URL] = [dir]
        if let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let u as URL in e { urls.append(u) }
        }
        for url in urls {
            _ = removeXattrIfExists(url, name: "com.apple.quarantine")
            _ = removeXattrIfExists(url, name: "com.apple.FinderInfo")
            try? fm.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: url.path)
            do {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
                    let perms: Int16 = isDir.boolValue ? 0o755 : 0o644
                    try fm.setAttributes([.posixPermissions: NSNumber(value: perms)], ofItemAtPath: url.path)
                }
            } catch {}
            do {
                var rv = URLResourceValues(); rv.isExcludedFromBackup = true
                var mutable = url; try mutable.setResourceValues(rv)
            } catch {}
        }
        let weight = dir.appendingPathComponent("weights/weight.bin")
        let size = ((try fm.attributesOfItem(atPath: weight.path)[.size]) as? NSNumber)?.int64Value ?? 0
        if size <= 0 {
            throw NSError(domain: "ModelPostProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "weights/weight.bin is empty or missing in \(dir.lastPathComponent)"])
        }
    }
    
    @discardableResult
    private static func removeXattrIfExists(_ url: URL, name: String) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let p = path else { return false }
            let res = removexattr(p, name, 0)
            return (res == 0 || errno == ENOATTR)
        }
    }
}
