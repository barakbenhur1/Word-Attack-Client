//
//  AIPackDownloadView.swift
//  Word Guess
//

import SwiftUI

private struct CapsuleProgressBar: View {
    var progress: Double
    var height: CGFloat = 18
    var body: some View {
        GeometryReader { geo in
            let w = max(0, min(1, progress)) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.25))
                Capsule().fill(LinearGradient(colors: [.yellow, .green],
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(width: w)
                    .shadow(color: .yellow.opacity(0.2), radius: 6, x: 0, y: 2)
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
    
    // Local state just for the short finalize check after download
    @State private var isLoadingModel = false
    @State private var finalizeError: String?   // <- local error, not mgr.errorText
    
    var body: some View {
        VStack {
            VStack(spacing: 24) {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .green], startPoint: .top, endPoint: .bottom))
                    .symbolRenderingMode(.hierarchical)
                    .shadow(radius: 6, y: 2)
                
                Text(isLoadingModel ? "Preparing AI Model" : "Downloading AI Pack")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 10) {
                    CapsuleProgressBar(progress: progressValue > 0.01 ? progressValue : 0, height: 20)
                        .frame(maxWidth: 520)
                        .padding(.horizontal)
                    HStack {
                        Text(progressLabel).monospacedDigit().font(.headline)
                        Spacer()
                        Text(sizeString(done: mgr.completedBytes, total: mgr.totalBytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal)
                }
                
                if let err = visibleError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
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
            .padding(.top, 280)
            .padding(.horizontal)
            Spacer()
        }
        .task {
            if ModelStorage.localHasUsableModels() { downloaded = true }
            else { mgr.ensurePackReady() } // starts GitHub download
        }
        .onAppear { mgr.migrateIfNeeded() }
        .onDisappear { mgr.cancel() }         // stop any in-flight downloads
        .onChange(of: mgr.isReady) { _, ready in if ready { validateThenPersistAll() } }
    }
    
    // MARK: - UI helpers
    
    private var progressValue: Double { isLoadingModel ? 1.0 : mgr.progress }
    
    private var progressLabel: String {
        isLoadingModel
        ? "Finalizing…"
        : "\(Int((max(0, min(1, mgr.progress))) * 100))% \("complete".localized)"
    }
    
    private var visibleError: String? {
        finalizeError ?? mgr.errorText
    }
    
    // MARK: - Finalize after Git download
    
    private func validateThenPersistAll() {
        guard !isLoadingModel else { return }
        isLoadingModel = true
        finalizeError = nil
        
        let fm = FileManager.default
        if let root = mgr.installRoot {
            ModelStorage.setInstallRoot(root)
            let hasDecode  = fm.fileExists(atPath: root.appendingPathComponent("WordleGPT_decode.mlmodelc").path)
            let hasPrefill = fm.fileExists(atPath: root.appendingPathComponent("WordleGPT_prefill.mlmodelc").path)
            
            if hasDecode || hasPrefill {
                // If you need to register the root with your model loader, do it here.
                withAnimation { downloaded = true }
                isLoadingModel = false
                return
            } else { finalizeError = "Downloaded assets are missing compiled model folders (.mlmodelc)." }
        } else { finalizeError = "Install folder not available yet." }
        
        isLoadingModel = false
    }
    
    private func sizeString(done: Int64, total: Int64) -> String {
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
