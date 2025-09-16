//
//  RuntimeMemBudget.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 16/09/2025.
//

import os
import UIKit

enum RuntimeMemBudget {
    /// Conservative bytes we allow for model working set (KV, logits, scratch).
    static func bytes() -> Int {
        let ram = ProcessInfo.processInfo.physicalMemory       // total RAM
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        
        // Base fraction: phones 8–12%, iPads 10–16%
        var frac: Double = isPad ? 0.14 : 0.10
        
        // Thermal headroom → allow more/less
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: frac += 0.02
        case .fair:    break
        case .serious: frac -= 0.02
        case .critical: frac -= 0.04
        @unknown default: break
        }
        
        // Floor/ceil
        let minB = isPad ? 220 * 1024 * 1024 : 140 * 1024 * 1024
        let maxB = isPad ? 420 * 1024 * 1024 : 280 * 1024 * 1024
        
        return min(max(Int(Double(ram) * frac), minB), maxB)
    }
    
    /// Simple “are we close to the edge?” check.
    static func lowMemoryLikely() -> Bool {
        // Heuristic: if app’s resident set > 80% of allowed budget, call it “low”.
        let rss = currentResidentMemory()
        return rss > bytes() * 8 / 10
    }
    
    static func currentResidentMemory() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), ptr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint) // bytes
    }
}
