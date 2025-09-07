//
//  DeepLinker.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 07/09/2025.
//

import SwiftUI
import GoogleSignIn

class DeepLinker: Singleton {
    private enum DifficultyType: String { case easy, medium, hard}
    
    private let router: Router
    private var deepLinkUrl: [URL]
    private var lastUrl: URL?
    
    override init() {
        router = Router.shared
        deepLinkUrl = []
    }
    
    func set(url: URL?) {
        guard let url else { return }
        deepLinkUrl.removeAll()
        deepLinkUrl.append(url)
    }
    
    func reset() {
        deepLinkUrl = []
        lastUrl = nil
    }
    
    func preform() {
        guard let url = deepLinkUrl.popLast(), url != lastUrl else { return }
        lastUrl = url
        if GIDSignIn.sharedInstance.handle(url) { return }
        Task(priority: .userInitiated) {
            await router.popToRoot()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                switch url.absoluteString {
                case let absoluteString where absoluteString.contains(.home): break
                case let absoluteString where absoluteString.contains(.settings):   router.navigateTo(.settings)
                case let absoluteString where absoluteString.contains(.scoreboard): router.navigateTo(.score)
                case let absoluteString where absoluteString.contains(.ai):         router.navigateTo(.game(diffculty: .ai))
                case let absoluteString where absoluteString.contains(.difficulty):
                    let comp = absoluteString.components(separatedBy: "=")
                    guard let rawValue = comp.last else { break }
                    switch DifficultyType(rawValue: rawValue) {
                    case .easy:                                                     router.navigateTo(.game(diffculty: .easy))
                    case .medium:                                                   router.navigateTo(.game(diffculty: .medium))
                    case .hard:                                                     router.navigateTo(.game(diffculty: .hard))
                    default: break
                    }
                default: break
                }
            }
        }
    }
}

private extension String {
    enum DeepLinkType: String { case home, settings, scoreboard, ai, difficulty}
    
    func contains(_ value: DeepLinkType) -> Bool {
        return contains(value.rawValue)
    }
}
