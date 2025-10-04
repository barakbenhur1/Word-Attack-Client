//
//  LLMService+WordZapAI.swift
//  WordZap
//
//  Loads the decoder model and exposes a KV “step” API.
//  Robust to .mlmodelc/.mlmodel and Storage/Bundle locations.
//

import Foundation
import CoreML

final class LLMService {
    private let model: MLModel
    private let decoder: KVTextDecoder
    
    // MARK: - Init
    
    init() throws {
        // Prefer decoder-only; fall back to unified
        let preferredNames = ["WordZapGPT_decode", "WordZapGPT"]
        
        // Resolve a usable URL to a compiled model (compile if required)
        let modelURL = try LLMService.resolveModelURL(possibleNames: preferredNames)
        
        // Configure compute units:
        //  - Simulator: CPU-only (GPU drivers differ, ANE not available)
        //  - Device: CPU+GPU (avoid ANE alignment problems some models hit)
        let cfg = MLModelConfiguration()
#if targetEnvironment(simulator)
        cfg.computeUnits = .cpuOnly
#else
        cfg.computeUnits = .cpuAndGPU
#endif
        
        self.model = try MLModel(contentsOf: modelURL, configuration: cfg)
        self.decoder = try KVTextDecoder(model: model)
    }
    
    // MARK: - Public API
    
    func resetSequence() throws {
        try decoder.reset()
    }
    
    /// Feed one token and return logits (ideally last-timestep slice of size `expectedVocab`).
    func step(tokenId: Int32, expectedVocab: Int) throws -> [Float] {
        let out = try decoder.generateStep(tokenId: tokenId, newTokens: 1)
        guard let logitsMA = LLMService.pickLogits(from: out, expectedVocab: expectedVocab) else {
            throw NSError(
                domain: "LLMService",
                code: -1002,
                userInfo: [NSLocalizedDescriptionKey: "Could not locate logits output in model prediction."]
            )
        }
        
        // Flatten
        var flat = [Float](repeating: 0, count: logitsMA.count)
        for i in 0..<logitsMA.count { flat[i] = logitsMA[i].floatValue }
        
        // Heuristics for the final slice
        if expectedVocab > 0 {
            if flat.count == expectedVocab { return flat }
            if flat.count % expectedVocab == 0 { return Array(flat.suffix(expectedVocab)) }
            if let last = logitsMA.shape.last?.intValue, last == expectedVocab {
                return Array(flat.suffix(expectedVocab))
            }
        }
        return flat
    }
    
    // MARK: - Model resolution helpers
    
    /// Finds the model in ModelStorage or Bundle. Accepts either:
    ///  - compiled: .../Name.mlmodelc  -> returned directly
    ///  - source:   .../Name.mlmodel   -> compiled then returned
    private static func resolveModelURL(possibleNames names: [String]) throws -> URL {
        // 1) Probe ModelStorage
        if let u = try findInModelStorage(names: names) {
            return try ensureCompiled(url: u)
        }
        
        // 2) Probe Bundle
        if let u = findInBundle(names: names) {
            return try ensureCompiled(url: u)
        }
        
        throw NSError(
            domain: "LLMService",
            code: -1001,
            userInfo: [NSLocalizedDescriptionKey:
                        "Decoder model not found (need WordZapGPT_decode(.mlmodelc/.mlmodel) or WordZapGPT)."]
        )
    }
    
    private static func findInModelStorage(names: [String]) throws -> URL? {
        for name in names {
            guard ModelStorage.modelExists(name) else { continue }
            // `modelDir(name:)` may return the package root; check common locations.
            let base = try ModelStorage.modelDir(name: name)
            
            // If the base itself is an .mlmodelc directory, return it
            if base.pathExtension == "mlmodelc" { return base }
            
            // Common inside-package paths
            let compiled = base.appendingPathComponent("\(name).mlmodelc")
            if FileManager.default.fileExists(atPath: compiled.path) { return compiled }
            
            let source = base.appendingPathComponent("\(name).mlmodel")
            if FileManager.default.fileExists(atPath: source.path) { return source }
            
            // Some exporters lay out just the compiled dir without the name
            if let contents = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
                if let directC = contents.first(where: { $0.pathExtension == "mlmodelc" }) { return directC }
                if let directM = contents.first(where: { $0.pathExtension == "mlmodel"  }) { return directM }
            }
        }
        return nil
    }
    
    private static func findInBundle(names: [String]) -> URL? {
        let b = Bundle.main
        for name in names {
            if let c = b.url(forResource: name, withExtension: "mlmodelc") { return c }
            if let m = b.url(forResource: name, withExtension: "mlmodel")  { return m }
        }
        return nil
    }
    
    /// If URL points to `.mlmodel`, compile it to `.mlmodelc` and return the compiled URL.
    /// If it’s already `.mlmodelc`, return as-is.
    private static func ensureCompiled(url: URL) throws -> URL {
        if url.pathExtension == "mlmodelc" { return url }
        if url.pathExtension == "mlmodel"  { return try MLModel.compileModel(at: url) }
        // Handle the case where a directory was returned without extension but is a compiled model
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // Heuristic: compiled CoreML packages are directories containing model.mil or similar
            // Try opening directly; if CoreML rejects, fall through to error.
            return url
        }
        throw NSError(
            domain: "LLMService",
            code: -1003,
            userInfo: [NSLocalizedDescriptionKey: "Unrecognized model URL: \(url.lastPathComponent)"]
        )
    }
    
    // MARK: - Logits picker
    
    private static func pickLogits(from out: MLFeatureProvider, expectedVocab: Int) -> MLMultiArray? {
        var best: (score: Int, arr: MLMultiArray)? = nil
        for name in out.featureNames {
            guard let ma = out.featureValue(for: name)?.multiArrayValue else { continue }
            // Likely KV tensors are 4D — skip them
            if ma.shape.count == 4 { continue }
            
            let dims = ma.shape.map(\.intValue)
            let count = ma.count
            var s = 0
            let lower = name.lowercased()
            if lower.contains("logit") || lower.contains("lm_head") ||
                lower.contains("probs") || lower.contains("softmax") { s += 10 }
            if expectedVocab > 0 {
                if dims.last == expectedVocab { s += 6 }
                if count == expectedVocab || (count % expectedVocab == 0) { s += 4 }
            }
            if dims.count <= 2 { s += 1 }
            if best == nil || s > best!.score { best = (s, ma) }
        }
        return best?.arr
    }
}
