//
//  Net.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 31/08/2025.
//

import Foundation

final class Net: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    static let shared = Net()
    lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.barak.wordzap.bg")
        cfg.isDiscretionary = true
        cfg.sessionSendsLaunchEvents = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()
    
    func prefetchLeaderboard(email: String) {
        let url = URL(string: "https://api.your.app/leaderboard?email=\(email)")!
        session.downloadTask(with: url).resume()
    }
    
    // Called when iOS finishes the download (even if your app was relaunched)
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        Task {
            // parse file -> write to SharedStore
            // then:
            await SharedStore.requestWidgetReload()
        }
    }
    
    // Required to reconnect background session events on relaunch:
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // If you use a completionHandler from SceneDelegate, call it here.
    }
}
