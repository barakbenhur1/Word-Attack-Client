//
//  AIPackDownloadView.swift
//  Word Guess
//

import SwiftUI
import CoreML

private enum AIAssetNames {
    static let preferredModelNames = ["WordleGPT_decode", "WordleGPT_prefill"]
    static let fallbackModelNames  = ["WordleGPT"]
    static let all = preferredModelNames + fallbackModelNames
    
    // Try both forms so copies succeed regardless of how the files were packaged
    static let sidecars = [
        "tokenizer", "tokenizer.json",
        "tokenizer_config", "tokenizer_config.json",
        "special_tokens_map", "special_tokens_map.json",
        "tokenizer.model",
        "config", "config.json",
        "WordleGPT_runtime_spec", "WordleGPT_runtime_spec.json"
    ]
}

private struct CapsuleProgressBar: View {
    var progress: Double
    var height: CGFloat = 18
    var body: some View {
        GeometryReader { geo in
            let w = max(0, min(1, progress)) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.25))
                Capsule()
                    .fill(LinearGradient(colors: [.blue, .purple],
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(width: w)
                    .shadow(color: .purple.opacity(0.2), radius: 6, x: 0, y: 2)
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.25), value: progress)
    }
}

struct AIPackDownloadView: View {
    @Binding var downloaded: Bool
    let onCancel: () -> Void
    
    @State private var mgr = AIPackManager()
    @State private var isLoadingModel = false
    @State private var loadError: String?
    @Environment(\.layoutDirection) private var dir
    
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                    .symbolRenderingMode(.hierarchical)
                    .shadow(radius: 6, y: 2)
                
                Text(isLoadingModel ? "Preparing AI Model" : "Downloading AI Pack")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 10) {
                    CapsuleProgressBar(progress: progressValue, height: 20)
                        .frame(maxWidth: 520).padding(.horizontal)
                    HStack {
                        Text(progressLabel).monospacedDigit().font(.headline)
                        Spacer()
                        Text(sizeString(done: mgr.completedBytes, total: mgr.totalBytes))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 520).padding(.horizontal)
                }
                
                if let err = visibleError {
                    Text(err).foregroundStyle(.red).font(.footnote)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                
                Button(role: .cancel) { onCancel() } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(Palette.buttonTint)
                .accessibilityLabel("Cancel")
            }
            .padding(.horizontal)
            Spacer()
        }
        .task {
            // If a usable local set exists, skip ODR entirely.
            if ModelStorage.localHasUsableModels() { downloaded = true }
            else { mgr.ensurePackReady(priority: 1.0, preserve: 0.95) }
        }
        .onAppear { mgr.migrateIfNeeded() }
        .onDisappear { mgr.releaseLease() }
        .onChange(of: mgr.isReady) { _, ready in if ready { validateThenPersistAll() } }  // validate while lease is active
        //        .opacity(mgr.isReady ? 0 : 1)
    }
    
    private func detectODRModelNames() -> [String] { AIAssetNames.all.filter { name in Bundle.main.url(forResource: name, withExtension: "mlmodelc") != nil } }
    
    // MARK: - Validate, copy, then release
    
    private func validateThenPersistAll() {
        guard !isLoadingModel else { return }
        isLoadingModel = true
        loadError = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 1) Ensure ODR actually contains any compiled models
                let names = detectODRModelNames()
                guard !names.isEmpty else { throw NSError(domain: "AIPack", code: 404,
                                                          userInfo: [NSLocalizedDescriptionKey:
                                                                        "No .mlmodelc found in ODR. Expected one of \(AIAssetNames.all)"]) }
                
                // 2) Copy + load (to validate) each model into versioned storage
                for name in names { _ = try ModelFactory.ensureLocalFromODRAndLoad(name: name) }
                
                // 3) Copy sidecars (best-effort)
                try ModelFactory.copySidecarsIfPresent(AIAssetNames.sidecars)
                
                // 5) Release ODR lease; local files now exist
                mgr.releaseLease()

                DispatchQueue.main.async {
                    withAnimation { downloaded = true }
                    isLoadingModel = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadError = error.localizedDescription
                    self.isLoadingModel = false
                }
            }
        }
    }
    
    // MARK: - UI helpers
    
    @ViewBuilder private func backButton() -> some View {
        BackButton(action: onCancel)
            .padding(.top, 20)
    }
    
    private var progressValue: Double { isLoadingModel ? 1.0 : mgr.progress }
    
    private var progressLabel: String {
        isLoadingModel ? "Finalizing…" : "\(Int((max(0, min(1, mgr.progress))) * 100))% complete"
    }
    
    private var visibleError: String? { loadError ?? mgr.errorText }
    
    private func sizeString(done: Int64, total: Int64) -> String {
        // If the system doesn't provide a known total, avoid "0 KB / 0 KB".
        guard total > 0 else { return done > 0 ? humanBytes(done) : "" }
        return "\(humanBytes(done)) / \(humanBytes(total))"
    }
    
    private func humanBytes(_ v: Int64) -> String {
        let kb = Double(v) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024.0)
    }
}
