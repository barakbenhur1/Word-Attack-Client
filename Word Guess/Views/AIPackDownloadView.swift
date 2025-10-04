//
//  AIPackDownloadView.swift
//  WordZap
//
//  Drop-in file: View + robust replace utils + minimal manager stubs.
//  Replace AIPackManager.ensurePackReady() with your real downloader.
//
//  Created by barak ben hur on 2025-09-06.
//

import SwiftUI
import Foundation

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
    @EnvironmentObject private var screenManager: ScreenManager
    @Binding var downloaded: Bool
    let onCancel: () -> Void
    
    @State private var mgr = AIPackManager()
    
    @State private var isLoadingModel = false
    @State private var finalizeError: String?
    
    private var progressValue: Double { isLoadingModel ? 1.0 : mgr.progress }
    
    private var visibleError: String? { finalizeError ?? mgr.errorText }
    
    private var progressLabel: String {
        isLoadingModel
        ? "Finalizing…".localized
        : "\(Int((max(0, min(1, mgr.progress))) * 100))% \("complete".localized)"
    }
    
    var body: some View {
        VStack {
            VStack(spacing: 24) {
                SafeSymbol("icloud.and.arrow.down.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .green], startPoint: .top, endPoint: .bottom))
                    .symbolRenderingMode(.multicolor)
                    .shadow(radius: 6, y: 2)
                
                Text(isLoadingModel ? "Saving AI Model" : "Downloading AI Pack")
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
                
                Button { onCancel() }
                label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.buttonTint)
                .buttonBorderShape(.capsule)
                .padding(.bottom, 14)
                .accessibilityLabel("Cancel")
            }
            .padding(.top, 280)
            .padding(.horizontal)
            Spacer()
        }
        .task {
            BackgroundDownloadCenter.shared.setMode(.foreground)
            if ModelStorage.localHasUsableModels() { downloaded = true }
            else { mgr.ensurePackReady() }
        }
        .onAppear {
            screenManager.keepScreenOn = true
            mgr.migrateIfNeeded()
        }
        .onDisappear {
            screenManager.keepScreenOn = false
            mgr.cancel()
        }
        .onChange(of: mgr.isReady) { _, ready in
            guard ready else { return }
            validateThenPersistAll(forceReplaceFrom: nil)
        }
    }
    
    private func SafeSymbol(_ name: String) -> Image {
      #if targetEnvironment(simulator)
      if #available(iOS 18.1, *) {
        return Image(systemName: name).renderingMode(.template).symbolRenderingMode(.multicolor)
      }
      #endif
      return Image(systemName: name)
    }
    
    /// Final check after downloader says ready; we only validate and set the install root.
    private func validateThenPersistAll(forceReplaceFrom stagingRoot: URL?) {
        guard !isLoadingModel else { return }
        isLoadingModel = true
        finalizeError = nil
        
        guard let root = mgr.installRoot else {
            finalizeError = "Install folder not available yet."
            return
        }
        
        ModelStorage.setInstallRoot(root)
        
        let fm = FileManager.default
        // (If you purposely pass a staging folder, we can replace here too.)
        if let staging = stagingRoot, fm.fileExists(atPath: staging.path) {
            do {
                try ModelPostProcessor.hardenExtractedModelDir(root.appendingPathComponent("WordZapGPT_decode.mlmodelc"))
                try ModelPostProcessor.hardenExtractedModelDir(root.appendingPathComponent("WordZapGPT_prefill.mlmodelc"))
            } catch { finalizeError = "Failed to finalize assets: \(error.localizedDescription)"; return }
        }
        
        let hasDecode  = fm.fileExists(atPath: root.appendingPathComponent("WordZapGPT_decode.mlmodelc").path)
        let hasPrefill = fm.fileExists(atPath: root.appendingPathComponent("WordZapGPT_prefill.mlmodelc").path)
        
        if hasDecode || hasPrefill {
            Task.detached(priority: .high) {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                await MainActor.run { downloaded = true }
            }
        } else { finalizeError = "Downloaded assets are missing compiled model folders (.mlmodelc)." }
    }
    
    private func sizeString(done: Int64, total: Int64) -> String {
        guard total > 0 else { return done > 0 ? humanBytes(done) : "" }
        return "\(humanBytes(done)) / \(humanBytes(total))"
    }
    
    private func humanBytes(_ v: Int64) -> String {
        let kb = Double(v) / 1024.0
        if kb < 1024 { return String(format: "%.0f \("KB".localized)", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f \("MB".localized)", mb) }
        return String(format: "%.2f \("GB".localized)", mb / 1024.0)
    }
}

//#if DEBUG
//struct AIPackDownloadView_Previews: PreviewProvider {
//    struct Host: View {
//        @State private var downloaded = false
//        var body: some View { AIPackDownloadView(downloaded: $downloaded) { } }
//    }
//    static var previews: some View { Host().preferredColorScheme(.dark) }
//}
//#endif
