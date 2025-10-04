//
//  BackgroundDownloadCenter.swift
//  WordZap
//
//  Created by Barak Ben Hur on 06/09/2025.
//

import Foundation

final class BackgroundDownloadCenter: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    static let shared = BackgroundDownloadCenter()
    
    // MARK: - Public callbacks
    var onProgress: ((String, Int64, Int64) -> Void)?
    var onFileReady: ((URL, String) -> Void)?
    var onTaskError: ((String, Error) -> Void)?
    var onAllTasksFinished: (() -> Void)?
    var backgroundCompletionHandler: (() -> Void)?
    
    // MARK: - Mode
    enum Mode { case foreground, background }
    private(set) var mode: Mode = .foreground   // default to foreground for stability
    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        // Recreate session with the right configuration.
        _session?.invalidateAndCancel()
        _session = nil
    }
    
    // MARK: - Sessions
    private var sessionIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.example.app") + ".ai-background-downloads"
    }
    private var _session: URLSession?
    
    private var session: URLSession {
        if let s = _session { return s }
        
        let cfg: URLSessionConfiguration
        switch mode {
        case .foreground:
            // Ephemeral, no caching; behaves like a normal foreground transfer.
            cfg = .ephemeral
            cfg.waitsForConnectivity = true
            cfg.httpMaximumConnectionsPerHost = 1
        case .background:
            // True background session handled by system daemon.
            cfg = .background(withIdentifier: sessionIdentifier)
            cfg.sessionSendsLaunchEvents = true
            cfg.waitsForConnectivity = true
            cfg.httpMaximumConnectionsPerHost = 1
        }
        
        cfg.allowsConstrainedNetworkAccess = true
        cfg.allowsExpensiveNetworkAccess = true
        
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        _session = s
        return s
    }
    
    // MARK: - Single-task bookkeeping
    private var activeTask: URLSessionDownloadTask?
    private var activeName: String?
    
    /// Start (or retry) a single download. Call `setMode(.foreground)` before this if you want foreground semantics.
    func startOne(name: String, request: URLRequest) {
        cancelAll()
        let t = session.downloadTask(with: request)
        t.taskDescription = name
        activeTask = t
        activeName = name
        t.resume()
    }
    
    func cancelAll() {
        activeTask?.cancel()
        activeTask = nil
        activeName = nil
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }
    
    /// AppDelegate should call this for background sessions.
    func reconnectSession(withIdentifier identifier: String) {
        guard mode == .background, identifier == sessionIdentifier else { return }
        _session?.invalidateAndCancel()
        _session = nil
        let s = session
        s.getAllTasks { [weak self] tasks in
            guard let self else { return }
            self.activeTask = tasks.first as? URLSessionDownloadTask
            self.activeName = self.activeTask?.taskDescription
        }
    }
    
    // MARK: - URLSession delegates
    
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let name = downloadTask.taskDescription ?? "asset"
        onProgress?(name,
                    totalBytesWritten,
                    totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : -1)
    }
    
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let name = downloadTask.taskDescription ?? "asset"
        
        // Surface HTTP failures (e.g., 403/404/5xx/618) instead of treating body as a file.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            onTaskError?(name,
                         NSError(domain: "ai.download",
                                 code: http.statusCode,
                                 userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) for \(name)"]))
            return
        }
        
        // Move to temp path while preserving filename.
        let tempDir = FileManager.default.temporaryDirectory
        var dest = tempDir.appendingPathComponent(name, isDirectory: false)
        if FileManager.default.fileExists(atPath: dest.path) {
            let ext = dest.pathExtension
            let base = dest.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString
            dest = tempDir.appendingPathComponent(ext.isEmpty ? base : base + "." + ext)
        }
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            onFileReady?(dest, name)
        } catch {
            onTaskError?(name, error)
        }
    }
    
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let err = error as NSError?, err.code != NSURLErrorCancelled {
            let name = task.taskDescription ?? "asset"
            onTaskError?(name, err)
        }
        if task == activeTask {
            activeTask = nil
            activeName = nil
        }
        onAllTasksFinished?()
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let handler = backgroundCompletionHandler {
            backgroundCompletionHandler = nil
            DispatchQueue.main.async { handler() }
        }
    }
}
