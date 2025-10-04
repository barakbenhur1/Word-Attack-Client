//
//  KVTextDecoder.swift
//  WordZap
//
//  Created by Barak Ben Hur on 16/08/2025.
//

import Foundation
import CoreML

/// A generic, robust KV decoder wrapper for “decoder-only” CoreML models.
/// It auto-detects common I/O names and keeps an internal sliding window KV cache.
final class KVTextDecoder {
    // Resolved names (auto-detected in init)
    private var inputIdsName: String = "input_ids"
    private var attentionMaskName: String = "attention_mask"
    private var pastKNameBuilder: (Int) -> String = { String(format: "past_k_%02d", $0) }
    private var pastVNameBuilder: (Int) -> String = { String(format: "past_v_%02d", $0) }
    private var presentKNameBuilder: (Int) -> String = { String(format: "present_k_%02d", $0) }
    private var presentVNameBuilder: (Int) -> String = { String(format: "present_v_%02d", $0) }

    private let model: MLModel

    // inferred from model description on init
    private(set) var numLayers: Int = 12
    private(set) var numHeads:  Int = 4
    private(set) var headDim:   Int = 64
    private(set) var window:    Int = 83

    // attention mask shape (read from model if available)
    private var attnMaskShape: [Int] = [1, 83]
    private var attnMaskType: MLMultiArrayDataType = .int32

    // rolling cache
    private var pastK: [MLMultiArray] = []
    private var pastV: [MLMultiArray] = []
    private var tokensInCache: Int = 0  // how many valid time steps currently populated (<= window)

    init(model: MLModel) throws {
        self.model = model
        try inferIO()
        try resetCache()
    }

    // MARK: API

    func debugPrintModelIO() { KVTextDecoder.printModelIO(model) }

    func reset() throws { try resetCache() }

    /// Run one decoding step (you feed 1 new token).
    @discardableResult
    func generateStep(tokenId: Int32, newTokens: Int = 1) throws -> MLFeatureProvider {
        var inputs: [String: Any] = [:]

        // a) token ids [1, 1]
        let ids = try MLMultiArray(shape: [1, 1], dataType: .int32)
        ids[0] = NSNumber(value: tokenId)
        inputs[inputIdsName] = ids

        // b) attention mask (zeros then ones for current valid length)
        let futureCount = min(tokensInCache + newTokens, window)
        inputs[attentionMaskName] = try makeAttentionMask(validCount: futureCount)

        // c) past cache
        for i in 0..<numLayers {
            inputs[pastKNameBuilder(i)] = pastK[i]
            inputs[pastVNameBuilder(i)] = pastV[i]
        }

        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))

        // 3) update cache from present_k_i / present_v_i
        for i in 0..<numLayers {
            let kName = presentKNameBuilder(i)
            let vName = presentVNameBuilder(i)
            guard
                let pk = out.featureValue(for: kName)?.multiArrayValue,
                let pv = out.featureValue(for: vName)?.multiArrayValue
            else { continue }
            try appendPresent(present: pk, intoPast: pastK[i])
            try appendPresent(present: pv, intoPast: pastV[i])
        }

        tokensInCache = futureCount
        return out
    }

    // MARK: Internals

    private func resetCache() throws {
        pastK.removeAll()
        pastV.removeAll()
        for _ in 0..<numLayers {
            let shape = [1, NSNumber(value: numHeads), NSNumber(value: window), NSNumber(value: headDim)]
            let k = try MLMultiArray(shape: shape, dataType: .float16)
            let v = try MLMultiArray(shape: shape, dataType: .float16)
            zeroFill(k); zeroFill(v)
            pastK.append(k); pastV.append(v)
        }
        tokensInCache = 0
    }

    private func inferIO() throws {
        let desc = model.modelDescription

        func pickInputName(_ candidates: [String]) -> String? {
            for c in candidates where desc.inputDescriptionsByName[c] != nil { return c }
            for (name, d) in desc.inputDescriptionsByName {
                if let m = d.multiArrayConstraint, m.dataType == .int32 { return name }
            }
            return desc.inputDescriptionsByName.keys.first
        }
        inputIdsName = pickInputName(["input_ids","tokens","token_ids","input"]) ?? "input_ids"
        attentionMaskName = pickInputName(["attention_mask","attn_mask","mask"]) ?? "attention_mask"

        // Layer count from either past_* or present_* names
        var layerCount = 0
        for i in 0..<128 {
            let names = [
                String(format: "past_k_%02d", i), "past_k_\(i)",
                String(format: "present_k_%02d", i), "present_k_\(i)"
            ]
            if names.contains(where: { desc.inputDescriptionsByName[$0] != nil || desc.outputDescriptionsByName[$0] != nil }) {
                layerCount = i + 1
            }
        }
        if layerCount > 0 { numLayers = layerCount }

        // Decide concrete naming (zero-padded vs non-padded)
        if desc.inputDescriptionsByName["past_k_00"] != nil || desc.outputDescriptionsByName["present_k_00"] != nil {
            pastKNameBuilder = { String(format: "past_k_%02d", $0) }
            pastVNameBuilder = { String(format: "past_v_%02d", $0) }
            presentKNameBuilder = { String(format: "present_k_%02d", $0) }
            presentVNameBuilder = { String(format: "present_v_%02d", $0) }
        } else if desc.inputDescriptionsByName["past_k_0"] != nil || desc.outputDescriptionsByName["present_k_0"] != nil {
            pastKNameBuilder = { "past_k_\($0)" }
            pastVNameBuilder = { "past_v_\($0)" }
            presentKNameBuilder = { "present_k_\($0)" }
            presentVNameBuilder = { "present_v_\($0)" }
        }

        // K/V shape
        if let s = desc.inputDescriptionsByName[pastKNameBuilder(0)]?.multiArrayConstraint?.shape.map({ $0.intValue }), s.count == 4 {
            numHeads = s[1]; window = s[2]; headDim = s[3]
        } else if let s = desc.outputDescriptionsByName[presentKNameBuilder(0)]?.multiArrayConstraint?.shape.map({ $0.intValue }), s.count == 4 {
            numHeads = s[1]; headDim  = s[3]
        }

        // attention mask shape/type
        if let m = desc.inputDescriptionsByName[attentionMaskName] {
            attnMaskType = m.multiArrayConstraint?.dataType ?? .int32
            if let s = m.multiArrayConstraint?.shape.map({ $0.intValue }), !s.isEmpty {
                attnMaskShape = s
                if let last = s.last { window = max(window, last) }
            }
        }
    }

    private static func printModelIO(_ model: MLModel) {
        let desc = model.modelDescription
        print("— INPUTS —")
        for (name, f) in desc.inputDescriptionsByName {
            print(" • \(name) :: \(f.type)")
            if let m = f.multiArrayConstraint {
                print("    shape=", m.shape.map { $0.intValue }, " dtype=", m.dataType.rawValue)
            }
        }
        print("— OUTPUTS —")
        for (name, f) in desc.outputDescriptionsByName {
            print(" • \(name) :: \(f.type)")
            if let m = f.multiArrayConstraint {
                print("    shape=", m.shape.map { $0.intValue }, " dtype=", m.dataType.rawValue)
            }
        }
    }

    // MARK: Attention mask

    private func makeAttentionMask(validCount: Int) throws -> MLMultiArray {
        let shape = attnMaskShape.map { NSNumber(value: $0) }
        let mask = try MLMultiArray(shape: shape, dataType: attnMaskType)
        zeroFill(mask)

        let W = (attnMaskShape.last ?? window)
        let ones = max(0, min(validCount, W))
        if ones == 0 { return mask }

        switch attnMaskShape.count {
        case 2: // [1, W]
            let s = mask.strides.map { $0.intValue }
            for t in (W - ones)..<W { mask[0 * s[0] + t * s[1]] = oneValue(attnMaskType) }
        case 3: // [1, 1, W]
            let s = mask.strides.map { $0.intValue }
            for t in (W - ones)..<W { mask[0 * s[0] + 0 * s[1] + t * s[2]] = oneValue(attnMaskType) }
        default:
            for i in 0..<mask.count { mask[i] = oneValue(attnMaskType) }
        }
        return mask
    }

    private func oneValue(_ t: MLMultiArrayDataType) -> NSNumber {
        switch t {
        case .float32, .float16, .double:  return 1.0
        case .int32:                       return 1
        default:                           return 1
        }
    }

    // MARK: Present -> Past appender (sliding window on time axis)

    private func appendPresent(present: MLMultiArray, intoPast past: MLMultiArray) throws {
        let pShape = present.shape.map { $0.intValue }
        let qShape = past.shape.map { $0.intValue }
        guard pShape.count == 4, qShape.count == 4 else { return }
        let H = qShape[1], W = qShape[2], D = qShape[3]
        let P = min(pShape[2], W)

        let ps = present.strides.map { $0.intValue }
        let qs = past.strides.map { $0.intValue }

        if P >= W {
            for h in 0..<H {
                for t in 0..<W {
                    for d in 0..<D {
                        past[0*qs[0] + h*qs[1] + t*qs[2] + d*qs[3]] =
                        present[0*ps[0] + h*ps[1] + (P - W + t)*ps[2] + d*ps[3]]
                    }
                }
            }
        } else {
            if tokensInCache + P >= W {
                let keep = W - P
                for h in 0..<H {
                    for t in 0..<keep {
                        for d in 0..<D {
                            past[0*qs[0] + h*qs[1] + t*qs[2] + d*qs[3]] =
                            past[0*qs[0] + h*qs[1] + (t + P)*qs[2] + d*qs[3]]
                        }
                    }
                }
                for h in 0..<H {
                    for t in 0..<P {
                        for d in 0..<D {
                            past[0*qs[0] + h*qs[1] + (W - P + t)*qs[2] + d*qs[3]] =
                            present[0*ps[0] + h*ps[1] + t*ps[2] + d*ps[3]]
                        }
                    }
                }
            } else {
                let start = tokensInCache
                for h in 0..<H {
                    for t in 0..<P {
                        for d in 0..<D {
                            past[0*qs[0] + h*qs[1] + (start + t)*qs[2] + d*qs[3]] =
                            present[0*ps[0] + h*ps[1] + t*ps[2] + d*ps[3]]
                        }
                    }
                }
            }
        }
    }

    private func zeroFill(_ a: MLMultiArray) { for i in 0..<a.count { a[i] = 0 } }
}
