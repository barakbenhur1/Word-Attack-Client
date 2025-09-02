import Foundation
import ZIPFoundation   // make sure the SPM package is added

actor SessionBox {
    let session: URLSession
    init(delegate: (any URLSessionDelegate)?) {
        let cfg = URLSessionConfiguration.default
        cfg.allowsExpensiveNetworkAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.timeoutIntervalForRequest = 60
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
    }
    func invalidate() { session.invalidateAndCancel() }
}

private struct GHRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int64
        let browser_download_url: URL
    }
    let tag_name: String
    let assets: [Asset]
}

@MainActor
@Observable
final class GitReleaseDownloader: NSObject, URLSessionDownloadDelegate {
    
    // MARK: Public (observed on MainActor)
    var progress: Double = 0
    var completedBytes: Int64 = 0
    var totalBytes: Int64 = -1
    var progressExtra: String?
    var isReady = false
    var errorText: String?
    var installedRoot: URL?
    
    // MARK: Internals (MainActor)
    private var box: SessionBox!                // IUO so we can assign after super.init
    private var activeTasks: [URLSessionDownloadTask] = []
    private var wanted: [Asset] = []
    private var nextIndex = 0
    private var running = false
    private var repo: Repo?
    private var tag: String?
    
    struct Repo {
        let owner: String
        let name:  String
        let token: String?
    }
    
    struct Asset: Hashable {
        let name: String
        let size: Int64
        let url:  URL
        let dest: URL
    }
    
    override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.allowsExpensiveNetworkAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.timeoutIntervalForRequest = 60
        cfg.waitsForConnectivity = true
        // Now we can reference `self` safely
        box = .init(delegate: self)
    }
    
    @MainActor
    func shutdown() async {
        await box?.invalidate()   // OK: await into the actor
    }
    
    // MARK: API
    
    func fetch(owner: String,
               repo: String,
               tag: String,
               version: Int,
               expectedAssetNames: [String],
               personalAccessToken: String? = nil)
    {
        guard !running else { return }
        
        // reset state
        progress = 0
        completedBytes = 0
        totalBytes = -1
        progressExtra = nil
        isReady = false
        errorText = nil
        self.repo = Repo(owner: owner, name: repo, token: personalAccessToken)
        self.tag = tag
        
        // resolve install root
        let fm = FileManager.default
        let base = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                               appropriateFor: nil, create: true)
            .appendingPathComponent("AIPack", isDirectory: true)
            .appendingPathComponent("v\(version)", isDirectory: true)
        
        do {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            self.fail("Couldn’t create install folder: \(error.localizedDescription)")
            return
        }
        self.installedRoot = base
        
        Task.detached { [expectedAssetNames, base] in
            do {
                guard let rel = try await Self.fetchRelease(owner: owner, repo: repo, tag: tag, token: personalAccessToken)
                else {
                    await self.fail("Release ‘\(tag)’ not found for \(owner)/\(repo). " +
                                    "Check the exact tag name (e.g. “ML_Models”), repo visibility, and token.")
                    return
                }
                
                // Compute list and total off the main thread
                var list: [Asset] = []
                var total: Int64 = 0
                let fm = FileManager.default
                
                for name in expectedAssetNames {
                    guard let remote = rel.assets.first(where: { $0.name == name }) else { continue }
                    let dest = base.appendingPathComponent(name, isDirectory: false)
                    
                    var need = true
                    if let attrs = try? fm.attributesOfItem(atPath: dest.path),
                       let localSize = attrs[.size] as? NSNumber,
                       localSize.int64Value == remote.size {
                        need = false
                    }
                    if need {
                        list.append(.init(name: name,
                                          size: remote.size,
                                          url: remote.browser_download_url,
                                          dest: dest))
                        total &+= max(0, remote.size)
                    }
                }
                
                // Hop to main with captured constants (Swift 6 rule)
                let wantedList = list
                let totalBytes = total
                await MainActor.run {
                    if wantedList.isEmpty {
                        self.totalBytes = 0
                        self.completedBytes = 0
                        self.progress = 1
                        self.progressExtra = self.progressExtra ?? NSLocalizedString("Ready", comment: "DL")
                        self.isReady = true
                        return
                    }
                    self.wanted = wantedList
                    self.totalBytes = totalBytes
                    self.updateExtra()
                    self.running = true
                    self.nextIndex = 0
                    self.startNext()
                }
            } catch {
                await self.fail(error.localizedDescription)
            }
        }
    }
    
    func cancel() {
        for t in activeTasks { t.cancel() }
        activeTasks.removeAll()
        running = false
    }
    
    // MARK: Drive one-by-one
    
    @MainActor
    private func startNext() {
        guard nextIndex < wanted.count else {
            running = false
            isReady = true
            progress = 1
            updateExtra()
            return
        }
        
        let item = wanted[nextIndex]
        
        var req = URLRequest(url: item.url)
        req.httpMethod = "GET"
        if let token = repo?.token, !token.isEmpty {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/octet-stream", forHTTPHeaderField: "Accept")
        
        // Encode the destination + unzip dir into taskDescription
        let unzipDir = (installedRoot ?? item.dest.deletingLastPathComponent()).path
        let meta = "\(item.dest.path)|\(unzipDir)"           // simple “dest|dir” format
        
        let task = box.session.downloadTask(with: req)
        task.taskDescription = meta
        activeTasks.append(task)
        task.resume()
    }
    
    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // ---- Do file work synchronously before returning ----
        do {
            guard let meta = downloadTask.taskDescription else {
                throw NSError(domain: "GitDL", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "Missing task metadata"])
            }
            let parts = meta.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw NSError(domain: "GitDL", code: -3,
                              userInfo: [NSLocalizedDescriptionKey: "Bad task metadata"])
            }
            
            let dest = URL(fileURLWithPath: parts[0])
            let unzipDir = URL(fileURLWithPath: parts[1])
            
            let fm = FileManager.default
            // Ensure parent exists (eliminates “folder … doesn’t exist”)
            try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            
            // Move/replace robustly (handles cross-volume temp files)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: location,
                                         backupItemName: nil,
                                         options: [.usingNewMetadataOnly])
            } else {
                do {
                    try fm.moveItem(at: location, to: dest)
                } catch {
                    try fm.copyItem(at: location, to: dest)
                    try? fm.removeItem(at: location)
                }
            }
            
            // Unzip if it’s a .zip
            if dest.pathExtension.lowercased() == "zip" {
                try fm.createDirectory(at: unzipDir, withIntermediateDirectories: true)
                let archive = try Archive(url: dest, accessMode: .read)
                for entry in archive {
                    let out = unzipDir.appendingPathComponent(entry.path)
                    try fm.createDirectory(at: out.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    _ = try archive.extract(entry, to: out)
                }
                try? fm.removeItem(at: dest) // remove the zip
            }
        } catch {
            // Hop to main only to surface the error and stop
            Task { @MainActor in
                self.fail(error.localizedDescription)
            }
            return
        }
        
        // ---- Now update state on the main actor ----
        Task { @MainActor in
            self.nextIndex &+= 1
            self.startNext()
        }
    }
    
    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            let prior = self.wanted.prefix(self.nextIndex).reduce(Int64(0)) { $0 &+ $1.size }
            self.completedBytes = max(0, prior &+ totalBytesWritten)
            if self.totalBytes > 0 {
                self.progress = min(1, Double(self.completedBytes) / Double(self.totalBytes))
            } else {
                self.progress = 0
            }
            self.updateExtra()
        }
    }
    
    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        Task { @MainActor in
            if let error, (error as NSError).code != NSURLErrorCancelled {
                self.fail(error.localizedDescription)
            }
        }
    }
    
    // MARK: Helpers
    
    @MainActor
    private func fail(_ msg: String) {
        errorText = msg
        running = false
        activeTasks.removeAll()
        progress = 0
    }
    
    @MainActor
    private func updateExtra() {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = .useAll
        fmt.countStyle = .file
        let done = fmt.string(fromByteCount: completedBytes)
        if totalBytes > 0 {
            let tot = fmt.string(fromByteCount: totalBytes)
            progressExtra = "\(done) of \(tot)"
        } else {
            progressExtra = done
        }
    }
    
    // Unzip `.zip` files into `dir`, then delete the `.zip`
    @MainActor
    private func unpackIfNeeded(archiveURL: URL, into dir: URL) throws {
        guard archiveURL.pathExtension.lowercased() == "zip" else { return }
        
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let archive = try Archive(url: archiveURL, accessMode: .read)
        
        // 1) Collect top-level names inside the zip (e.g. "WordleGPT_prefill.mlmodelc")
        var topLevelNames = Set<String>()
        for entry in archive {
            if let firstComponent = entry.path.split(separator: "/").first {
                topLevelNames.insert(String(firstComponent))
            }
        }
        
        // 2) Remove any existing top-level folders so we get a clean overwrite
        for name in topLevelNames {
            let topURL = dir.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: topURL.path) {
                try? fm.removeItem(at: topURL)
            }
        }
        
        // 3) Extract each entry, ensuring parent directories exist and removing any existing file
        for entry in archive {
            let outURL = dir.appendingPathComponent(entry.path)
            try fm.createDirectory(at: outURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            if fm.fileExists(atPath: outURL.path) {
                try? fm.removeItem(at: outURL)
            }
            _ = try archive.extract(entry, to: outURL)
        }
        
        // 4) Remove the .zip after successful extraction
        try? fm.removeItem(at: archiveURL)
    }
    
    // MARK: GitHub API
    
    private static func fetchRelease(owner: String,
                                     repo: String,
                                     tag: String,
                                     token: String?) async throws -> GHRelease? {
        // Small helper to send a request
        func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: url)
            req.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if let token, !token.isEmpty {
                req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw NSError(domain: "GitHub", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
            }
            return (data, http)
        }
        
        // 1) Try the exact tag first
        let base = "https://api.github.com/repos/\(owner)/\(repo)/releases"
        let exactURL = URL(string: "\(base)/tags/\(tag)")!
        
        do {
            let (data, http) = try await get(exactURL)
            if (200..<300).contains(http.statusCode) {
                return try JSONDecoder().decode(GHRelease.self, from: data)
            }
            if http.statusCode != 404 {
                throw NSError(domain: "GitHub", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "GitHub API \(http.statusCode) for tag \(tag)"])
            }
        } catch { /* fall through to variations */ }
        
        // 2) Try common variations: v-prefix and underscore/dash/no-separator
        let variants: [String] = {
            var arr = [String]()
            arr.append(tag.hasPrefix("v") ? String(tag.dropFirst()) : "v\(tag)")
            arr.append(tag.replacingOccurrences(of: "_", with: "-"))
            arr.append(tag.replacingOccurrences(of: "-", with: "_"))
            arr.append(tag.replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: ""))
            return Array(Set(arr)).filter { $0 != tag }
        }()
        
        for candidate in variants {
            let url = URL(string: "\(base)/tags/\(candidate)")!
            do {
                let (data, http) = try await get(url)
                if (200..<300).contains(http.statusCode) {
                    return try JSONDecoder().decode(GHRelease.self, from: data)
                }
            } catch { /* try next */ }
        }
        
        // 3) As a last resort, list releases and match loosely (case-insensitive, ignore _/-)
        do {
            let url = URL(string: base)!
            let (data, http) = try await get(url)
            if (200..<300).contains(http.statusCode) {
                struct R: Decodable { let tag_name: String; let assets: [GHRelease.Asset] }
                let list = try JSONDecoder().decode([R].self, from: data)
                func norm(_ s: String) -> String {
                    s.lowercased().replacingOccurrences(of: "_", with: "")
                        .replacingOccurrences(of: "-", with: "")
                }
                if let r = list.first(where: { norm($0.tag_name) == norm(tag) }) {
                    return GHRelease(tag_name: r.tag_name, assets: r.assets)
                }
            }
        } catch { /* ignore */ }
        
        return nil // not found after all attempts
    }
}
