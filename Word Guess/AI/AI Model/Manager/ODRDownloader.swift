//
//  ODRDownloader.swift
//  Word Guess
//  Created by Barak Ben Hur on 15/08/2025.
//

import Foundation

@Observable
final class ODRDownloader: NSObject {
    // Public state (mutate/read on main)
    var progress: Double = 0            // 0...1
    var completedBytes: Int64 = 0
    var totalBytes: Int64 = -1          // -1 => unknown
    var progressExtra: String?          // e.g. "12.3 MB of 48.7 MB"
    var isReady = false
    var errorText: String?
    
    // Internals
    private var request: NSBundleResourceRequest?
    private var observations: [NSKeyValueObservation] = []
    private var didCallBegin = false
    
    /// Start once per lifecycle. Subsequent calls are ignored while a request exists.
    func fetch(tag: String, priority: Double = 1.0, preserve: Double = 0.95) {
        guard request == nil else { return }
        
        let r = NSBundleResourceRequest(tags: [tag])
        r.loadingPriority = priority
        request = r
        
        r.conditionallyBeginAccessingResources { [weak self] available in
            guard let self else { return }
            if available {
                Bundle.main.setPreservationPriority(preserve, forTags: [tag])
                DispatchQueue.main.async {
                    self.progress = 1
                    if self.totalBytes < 0 { self.totalBytes = 0 }
                    self.progressExtra = self.progressExtra ?? NSLocalizedString("Ready", comment: "ODR")
                    self.isReady = true
                }
                return
            }
            
            // Not cached: observe progress on main
            DispatchQueue.main.async { [weak self] in
                self?.startObservingProgress(of: r)
            }
            
            // Begin downloading
            self.beginIfNeeded(r: r, preserve: preserve, tag: tag)
        }
    }
    
    /// Safe to call from any thread. Hops to main when needed.
    func endAccessing() {
        if Thread.isMainThread {
            endAccessingImmediate()
        } else {
            DispatchQueue.main.async { [self] in endAccessingImmediate() }
        }
    }
    
    deinit { endAccessingImmediate() }
    
    // MARK: - Private
    
    private func beginIfNeeded(r: NSBundleResourceRequest, preserve: Double, tag: String) {
        guard !didCallBegin else { return }
        didCallBegin = true
        
        r.beginAccessingResources { [weak self] err in
            guard let self else { return }
            if let err {
                DispatchQueue.main.async {
                    self.errorText = err.localizedDescription
                    self.isReady = false
                }
            } else {
                Bundle.main.setPreservationPriority(preserve, forTags: [tag])
                DispatchQueue.main.async {
                    self.progress = 1
                    self.progressExtra = NSLocalizedString("Finalizing…", comment: "ODR")
                    self.isReady = true
                }
            }
        }
    }
    
    private func startObservingProgress(of r: NSBundleResourceRequest) {
        assert(Thread.isMainThread, "startObservingProgress must run on main")
        
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        
        let p = r.progress
        
        let o1 = p.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] prog, _ in
            DispatchQueue.main.async { [weak self] in
                self?.progress = max(0, min(1, prog.fractionCompleted))
            }
        }
        let o2 = p.observe(\.completedUnitCount, options: [.initial, .new]) { [weak self] prog, _ in
            DispatchQueue.main.async { [weak self] in
                self?.completedBytes = prog.completedUnitCount
            }
        }
        let o3 = p.observe(\.totalUnitCount, options: [.initial, .new]) { [weak self] prog, _ in
            DispatchQueue.main.async { [weak self] in
                // 0 or negative generally means "unknown"
                self?.totalBytes = prog.totalUnitCount > 0 ? prog.totalUnitCount : -1
            }
        }
        // This is the human-friendly "12.3 MB of 48.7 MB" string we want.
        let o4 = p.observe(\.localizedAdditionalDescription, options: [.initial, .new]) { [weak self] prog, _ in
            DispatchQueue.main.async { [weak self] in
                // Avoid showing a blank; nil means we’ll fall back to our manual formatter.
                self?.progressExtra = prog.localizedAdditionalDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        observations = [o1, o2, o3, o4]
    }
    
    /// Centralized cleanup. Called synchronously from deinit, or on main from `endAccessing()`.
    private func endAccessingImmediate() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        request?.endAccessingResources()
        request = nil
        didCallBegin = false
        progressExtra = nil
    }
}
