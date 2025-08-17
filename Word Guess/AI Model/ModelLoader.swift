//
//  ModelLoader.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 15/08/2025.
//

import Foundation
import CoreML

enum ModelLoaderError: Error {
    case resourceNotFound(String)
}

enum ModelLocations {
    /// Bundle/ODR model location (source).
    static func odrModelURL(name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mlmodelc")
    }

    /// Versioned local destination folder.
    static func localModelURL(name: String) throws -> URL {
        try ModelStorage.modelDir(name: name)
    }
}

enum ModelFileOps {
    static func copyIfNeeded(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) { return }
        try fm.copyItem(at: src, to: dst)
    }

    static func copyFileIfNeeded(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) { return }
        try fm.copyItem(at: src, to: dst)
    }
}

enum ModelFactory {
    /// Load from local versioned folder.
    static func loadLocal(name: String) throws -> MLModel {
        let url = try ModelLocations.localModelURL(name: name)
        return try MLModel(contentsOf: url)
    }

    /// Ensure local copy exists by copying from ODR, then load.
    static func ensureLocalFromODRAndLoad(name: String) throws -> MLModel {
        guard let src = ModelLocations.odrModelURL(name: name) else {
            throw ModelLoaderError.resourceNotFound("\(name).mlmodelc (ODR)")
        }
        let dst = try ModelLocations.localModelURL(name: name)
        try ModelFileOps.copyIfNeeded(from: src, to: dst)
        return try MLModel(contentsOf: dst)
    }

    /// Best-effort copy of sidecars into the versioned folder.
    static func copySidecarsIfPresent(_ basenames: [String]) throws {
        let root = try ModelStorage.versionedRoot()
        let exts = ["", ".json", ".model", ".txt"]

        for base in basenames {
            for ext in exts {
                let name = base.hasSuffix(ext) ? base : base + ext
                let stem = (name as NSString).deletingPathExtension
                let extn = (name as NSString).pathExtension
                if let src = Bundle.main.url(forResource: stem, withExtension: extn.isEmpty ? nil : extn) {
                    let dst = root.appendingPathComponent(src.lastPathComponent)
                    try? ModelFileOps.copyFileIfNeeded(from: src, to: dst)
                    break
                }
            }
        }
    }
}
