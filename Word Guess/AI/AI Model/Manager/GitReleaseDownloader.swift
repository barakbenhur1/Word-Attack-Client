//
//  GitReleaseDownloader.swift
//  WordZap
//
//  Created by Barak Ben Hur on 15/08/2025.
//

import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

@MainActor
@Observable
final class GitReleaseDownloader {
    // Observables
    var progress: Double = 0
    var completedBytes: Int64 = 0
    var totalBytes: Int64 = -1
    var progressExtra: String?
    var errorText: String?
    var isReady: Bool = false
    var installedRoot: URL?

    // Internals
    private var versionRoot: URL?
    private var stagingRoot: URL?

    // Current asset
    private var assetsOrder: [String] = []
    private var assetsMeta: [String: (apiURL: URL, browserURL: URL?, size: Int64)] = [:]
    private var idx: Int = 0
    private var retries: Int = 0

    // Token supplier
    private var tokenProvider: () -> String? = { AIPack.ghToken }

    // MARK: API

    func fetch(owner: String,
               repo: String,
               tag: String,
               version: Int,
               expectedAssetNames: [String],
               personalAccessToken: String?) {

        if let personalAccessToken { tokenProvider = { personalAccessToken } }

        progress = 0; completedBytes = 0; totalBytes = -1
        errorText = nil; isReady = false
        progressExtra = "Preparing…"
        assetsOrder = expectedAssetNames
        assetsMeta.removeAll(); idx = 0; retries = 0
        installedRoot = nil; versionRoot = nil; stagingRoot = nil

        do {
            let fm = FileManager.default
            let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("AIPack", isDirectory: true)
            let vr = base.appendingPathComponent("v\(version)", isDirectory: true)
            try fm.ensureDirectory(at: vr)
            versionRoot = vr
            installedRoot = vr
            if hasUsableModels(at: vr) { isReady = true; return }
        } catch {
            errorText = error.localizedDescription
            return
        }

        Task {
            do {
                try await loadRelease(owner: owner, repo: repo, tag: tag)
                try await startNext()
            } catch {
                self.errorText = error.localizedDescription
            }
        }
    }

    func cancel() { BackgroundDownloadCenter.shared.cancelAll() }
    func shutdown() async { }

    // MARK: Release resolution

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browser_download_url: String?
            let url: String?   // API asset URL
        }
        let assets: [Asset]
    }

    private func loadRelease(owner: String, repo: String, tag: String) async throws {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(tag)")!
        var req = URLRequest(url: url)
        req.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.addValue(ua(), forHTTPHeaderField: "User-Agent")
        if let t = tokenProvider() { req.addValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "ai.pack", code: 100, userInfo: [NSLocalizedDescriptionKey: "GitHub release fetch failed"])
        }
        let rel = try JSONDecoder().decode(Release.self, from: data)

        var total: Int64 = 0
        let byName = Dictionary(uniqueKeysWithValues: rel.assets.map { ($0.name, $0) })
        for name in assetsOrder {
            guard let a = byName[name],
                  let api = a.url.flatMap(URL.init(string:)) else { continue }
            assetsMeta[name] = (apiURL: api,
                                browserURL: a.browser_download_url.flatMap(URL.init(string:)),
                                size: max(0, a.size))
            total += max(0, a.size)
        }
        totalBytes = total > 0 ? total : -1
    }

    // MARK: Start/Retry (presign every time)

    private func startNext() async throws {
        #if canImport(UIKit)
        let isActive = UIApplication.shared.applicationState == .active
        BackgroundDownloadCenter.shared.setMode(isActive ? .foreground : .background)
        #endif

        guard idx < assetsOrder.count else { finalize(); return }
        let name = assetsOrder[idx]
        guard let meta = assetsMeta[name] else { idx += 1; try await startNext(); return }

        progressExtra = "Downloading \(name)…"
        retries = 0

        do {
            let presigned = try await resolvePresignedURL(apiURL: meta.apiURL)
            let req = URLRequest(url: presigned)
            wireCallbacksOnce()
            BackgroundDownloadCenter.shared.startOne(name: name, request: req)
        } catch {
            let status = (error as NSError).code
            errorText = "[\(name)] presign failed\(status > 0 ? " (\(status))" : "") — retrying…"
            await scheduleRetry(name: name, meta: meta)
        }
    }

    private func retry(for name: String, httpStatus: Int?) {
        guard let meta = assetsMeta[name] else { return }
        Task { @MainActor in
            await scheduleRetry(name: name, meta: meta, httpStatus: httpStatus)
        }
    }

    private func scheduleRetry(name: String,
                               meta: (apiURL: URL, browserURL: URL?, size: Int64),
                               httpStatus: Int? = nil) async {
        retries += 1
        if retries <= 3 {
            let delay: TimeInterval = [2.0, 5.0, 10.0][min(retries-1, 2)]
            errorText = "[\(name)] \(httpStatus.map { "HTTP \($0)" } ?? "network") — retry \(retries)/3 in \(Int(delay))s"
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            do {
                errorText = nil
                let presigned = try await resolvePresignedURL(apiURL: meta.apiURL)
                BackgroundDownloadCenter.shared.startOne(name: name, request: URLRequest(url: presigned))
            } catch {
                if retries >= 3, let b = meta.browserURL {
                    errorText = "[\(name)] trying browser fallback…"
                    BackgroundDownloadCenter.shared.startOne(name: name, request: URLRequest(url: b))
                    retries = 99
                } else {
                    await scheduleRetry(name: name, meta: meta, httpStatus: (error as NSError).code)
                }
            }
            return
        }
        errorText = "[\(name)] failed after retries."
    }

    // Resolve API asset → presigned download URL without following the redirect.
    private func resolvePresignedURL(apiURL: URL) async throws -> URL {
        @MainActor
        final class RedirectCatcher: NSObject, URLSessionTaskDelegate {
            var location: URL?
            func urlSession(_ session: URLSession, task: URLSessionTask,
                            willPerformHTTPRedirection response: HTTPURLResponse,
                            newRequest request: URLRequest) async -> URLRequest? {
                self.location = request.url
                return nil
            }
        }

        let catcher = RedirectCatcher()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = true
        let session = URLSession(configuration: cfg, delegate: catcher, delegateQueue: nil)

        var req = URLRequest(url: apiURL)
        req.addValue("application/octet-stream", forHTTPHeaderField: "Accept")
        req.addValue(ua(), forHTTPHeaderField: "User-Agent")
        if let t = tokenProvider() { req.addValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, resp) = try await session.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "ai.presign", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        if (300..<400).contains(http.statusCode),
           let loc = catcher.location ?? (http.allHeaderFields["Location"] as? String).flatMap(URL.init(string:)) {
            return loc
        }
        throw NSError(domain: "ai.presign", code: http.statusCode,
                      userInfo: [NSLocalizedDescriptionKey: "Unexpected status \(http.statusCode)"])
    }

    private func ua() -> String {
        "WordGuess/1.0 (+\(Bundle.main.bundleIdentifier ?? "app"))"
    }

    // MARK: Wiring (once)

    private var wired = false
    private func wireCallbacksOnce() {
        guard !wired else { return }
        wired = true

        BackgroundDownloadCenter.shared.onProgress = { [weak self] name, written, _ in
            guard let self else { return }
            self.completedBytes = (self.assetsOrder[..<self.idx].reduce(0) { $0 + (self.assetsMeta[$1]?.size ?? 0) }) + written
            if self.totalBytes > 0 {
                self.progress = Double(self.completedBytes) / Double(self.totalBytes)
            }
        }

        BackgroundDownloadCenter.shared.onFileReady = { [weak self] tmp, name in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try self.stage(tempItem: tmp, assetName: name)
                    self.idx += 1
                    try await self.startNext()
                } catch {
                    self.errorText = error.localizedDescription
                }
            }
        }

        BackgroundDownloadCenter.shared.onTaskError = { [weak self] name, err in
            Task { @MainActor in
                guard let self else { return }
                let status = (err as NSError).domain == "ai.download" ? (err as NSError).code : nil
                self.retry(for: name, httpStatus: status)
            }
        }

        BackgroundDownloadCenter.shared.onAllTasksFinished = { /* sequential; no-op */ }
    }

    // MARK: Stage & finalize

    private func stage(tempItem: URL, assetName: String) throws {
        let fm = FileManager.default
        if stagingRoot == nil {
            stagingRoot = fm.temporaryDirectory.appendingPathComponent("ai-stage-\(UUID().uuidString)")
            try fm.ensureDirectory(at: stagingRoot!)
        }

        func fileSize(_ url: URL) -> Int64 {
            (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1
        }
        func isZip(_ url: URL) -> Bool {
            guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? fh.close() }
            let sig = try? fh.read(upToCount: 4)
            guard let s = sig, s.count == 4 else { return false }
            let b = [UInt8](s)
            return (b == [0x50,0x4B,0x03,0x04]) || (b == [0x50,0x4B,0x05,0x06]) || (b == [0x50,0x4B,0x07,0x08])
        }

        if assetName.hasSuffix(".zip") {
            #if canImport(ZIPFoundation)
            guard isZip(tempItem) else {
                let sz = fileSize(tempItem)
                throw NSError(domain: "ai.pack", code: 1201, userInfo: [
                    NSLocalizedDescriptionKey:
                        "Downloaded file for \(assetName) is not a ZIP (size \(sz >= 0 ? "\(sz) bytes" : "unknown"))."
                ])
            }
            let archive = try Archive(url: tempItem, accessMode: .read)
            try archive.extractAll(to: stagingRoot!)
            #else
            throw NSError(domain: "ai.pack", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "ZIPFoundation not present. Add it via SPM."])
            #endif
        } else {
            let dest = stagingRoot!.appendingPathComponent(assetName)
            try fm.replaceItemAtOrMove(from: tempItem, to: dest)
        }
    }

    private func finalize() {
        guard let dst = versionRoot else {
            errorText = "Install root missing"
            return
        }
        let fm = FileManager.default
        do {
            try fm.ensureDirectory(at: dst)

            if let stage = stagingRoot, fm.fileExists(atPath: stage.path) {
                let contents = try fm.contentsOfDirectory(atPath: stage.path)
                guard !contents.isEmpty else {
                    errorText = "Downloaded staging folder is empty."
                    return
                }
                try fm.replaceDirectoryTree(from: stage, to: dst)
            } else {
                errorText = "Staging folder not found."
                return
            }

            if hasUsableModels(at: dst) { isReady = true }
            else { errorText = "Downloaded assets are missing compiled model folders (.mlmodelc)." }
        } catch {
            errorText = "Failed to finalize assets: \(error.localizedDescription)"
        }
    }

    private func hasUsableModels(at root: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: root.appendingPathComponent("WordZapGPT_decode.mlmodelc").path)
            || fm.fileExists(atPath: root.appendingPathComponent("WordZapGPT_prefill.mlmodelc").path)
    }
}

#if canImport(ZIPFoundation)
private extension Archive {
    func extractAll(to dest: URL) throws {
        let fm = FileManager.default
        try fm.ensureDirectory(at: dest)
        for entry in self {
            let outURL = dest.appendingPathComponent(entry.path)
            if entry.type == .directory {
                try fm.ensureDirectory(at: outURL)
            } else {
                try fm.ensureDirectory(at: outURL.deletingLastPathComponent())
                _ = try self.extract(entry, to: outURL,
                                     bufferSize: 32_768,
                                     skipCRC32: false,
                                     allowUncontainedSymlinks: true,
                                     progress: nil)
            }
        }
    }
}
#endif
