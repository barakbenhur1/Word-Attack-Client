//
//  LLMService+WordleAI.swift
//  Word Guess
//
//  Loads the compiled decoder model (WordleGPT_decode.mlmodelc) and exposes a KV “step” API.
//

import Foundation
import CoreML

final class LLMService {
    private let model: MLModel
    private let decoder: KVTextDecoder
    
    init() throws {
        // Prefer the decoder-only pack; fall back to unified model if present.
        let url: URL
        if ModelStorage.modelExists("WordleGPT_decode") {
            url = try ModelStorage.modelDir(name: "WordleGPT_decode")
        } else if ModelStorage.modelExists("WordleGPT") {
            url = try ModelStorage.modelDir(name: "WordleGPT")
        } else {
            throw NSError(
                domain: "LLMService",
                code: -1001,
                userInfo: [NSLocalizedDescriptionKey:
                    "Decoder model not found in ModelStorage (need WordleGPT_decode.mlmodelc or WordleGPT.mlmodelc)."]
            )
        }
        
        let cfg = MLModelConfiguration()
        #if targetEnvironment(simulator)
        cfg.computeUnits = .cpuOnly
        #else
        cfg.computeUnits = .cpuAndNeuralEngine
        #endif
        
        self.model = try MLModel(contentsOf: url, configuration: cfg)
        self.decoder = try KVTextDecoder(model: model)
    }
    
    func resetSequence() throws {
        try decoder.reset()
    }
    
    /// Feed one token and return the logits vector (length == expectedVocab when possible).
    func step(tokenId: Int32, expectedVocab: Int) throws -> [Float] {
        let out = try decoder.generateStep(tokenId: tokenId, newTokens: 1)
        guard let logitsMA = LLMService.pickLogits(from: out, expectedVocab: expectedVocab) else {
            throw NSError(
                domain: "LLMService",
                code: -1002,
                userInfo: [NSLocalizedDescriptionKey: "Could not locate logits output in model prediction."]
            )
        }
        
        // Flatten to [Float]
        var flat = [Float](repeating: 0, count: logitsMA.count)
        for i in 0..<logitsMA.count { flat[i] = logitsMA[i].floatValue }
        
        // Heuristics: return last time-step slice of size expectedVocab when identifiable.
        if expectedVocab > 0 {
            if flat.count == expectedVocab { return flat }
            if flat.count % expectedVocab == 0 { return Array(flat.suffix(expectedVocab)) }
            if let last = logitsMA.shape.last?.intValue, last == expectedVocab {
                return Array(flat.suffix(expectedVocab))
            }
        }
        return flat
    }
    
    // MARK: - Logits picker
    
    private static func pickLogits(from out: MLFeatureProvider, expectedVocab: Int) -> MLMultiArray? {
        var best: (score: Int, arr: MLMultiArray)? = nil
        for name in out.featureNames {
            guard let ma = out.featureValue(for: name)?.multiArrayValue else { continue }
            // Skip likely KV tensors (often 4D)
            if ma.shape.count == 4 { continue }
            
            let dims = ma.shape.map(\.intValue)
            let count = ma.count
            var s = 0
            let lower = name.lowercased()
            if lower.contains("logit") || lower.contains("lm_head") || lower.contains("probs") || lower.contains("softmax") { s += 10 }
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
