//
//  DeepLinker.swift
//  WordZap
//
//  Created by Barak Ben Hur on 07/09/2025.
//

import SwiftUI
import GoogleSignIn

@Observable
class DeepLinker: Singleton {
    private let router: Router
    private var deepLinkUrl: [URL]
    
    var inviteRef: String?
    
    override init() {
        router = Router.shared
        deepLinkUrl = []
    }
    
    func set(url: URL?) {
        guard let url else { return }
        deepLinkUrl.removeAll()
        deepLinkUrl.append(url)
    }
    
    func preform() {
        guard let url = deepLinkUrl.popLast() else { return }
        if GIDSignIn.sharedInstance.handle(url) { return }
        Task(priority: .userInitiated) {
            await router.popToRoot()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                switch url.absoluteString {
                case let absoluteString where absoluteString.contains(.resume):     resume(url: url)
                case let absoluteString where absoluteString.contains(.invite):     invite(url: url)
                case let absoluteString where absoluteString.contains(.settings):   navigateTo(.settings)
                case let absoluteString where absoluteString.contains(.scoreboard): navigateTo(.score)
                case let absoluteString where absoluteString.contains(.ai):         navigateTo(.game(diffculty: .ai))
                case let absoluteString where absoluteString.contains(.difficulty): difficultyGame(url: url)
                default:                                                            break
                }
            }
        }
    }
}

private extension DeepLinker {
    func resume(url: URL) {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let gid = comps?.queryItems?.first(where: { $0.name == "gameID" })?.value {
            guard let id = DifficultyType(rawValue: gid) else { return }
            navigateTo(.game(diffculty: id))
        }
    }
    
    func difficultyGame(url: URL) {
        let comp = url.absoluteString.components(separatedBy: "=")
        guard let rawValue = comp.last else { return }
        guard let diffculty = DifficultyType(rawValue: rawValue) else { return }
        navigateTo(.game(diffculty: diffculty))
    }
    
    func invite(url: URL) {
        if url.scheme?.lowercased() == "wordzap" {
            if url.host?.lowercased() == "invite",
               let ref = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ref" })?.value,
               !ref.isEmpty {
                inviteRef = ref
            }
        } else if let host = url.host?.lowercased(), host == "wordzap.app" || host == "www.wordzap.app" {     // Universal link: https://wordzap.app/invite?ref=XYZ  (adjust host/path for your domain)
            let path = url.path.lowercased()
            if path == "/invite",
               let ref = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ref" })?.value,
               !ref.isEmpty {
                inviteRef = ref
            }
        }
    }
}

private extension DeepLinker {
    func navigateTo(_ route: Router.Route) {
        router.navigateToSync(route)
    }
}

private extension String {
    enum DeepLinkType: String { case home, settings, scoreboard, ai, difficulty, resume, invite}
    
    func toDeepLink() -> DeepLinkType? {
        return .init(rawValue: self)
    }
    
    func contains(_ value: DeepLinkType) -> Bool {
        return contains(value.rawValue)
    }
}
