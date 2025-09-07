//
//  Word_GuessApp.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI
import FirebaseAuth
import WidgetKit
import GoogleSignIn

@Observable
class LanguageSetting: ObservableObject { var locale = Locale.current }

@main
struct WordGuessApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var vm = AppStateViewModel()
    
    @State private var tooltipPusher = PhraseProvider()
    @State private var deepLinkUrl: URL? = nil
    
    private let persistenceController = PersistenceController.shared
    private let loginHaneler = LoginHandeler()
    private let screenManager = ScreenManager.shared
    private let audio = AudioPlayer()
    private let local = LanguageSetting()
    private let router = Router()
    private let login = LoginViewModel()
    
    var body: some Scene {
        WindowGroup {
            RouterView {
                if loginHaneler.model == nil { LoginView() }
                else if loginHaneler.hasGender { DifficultyView() }
                else { ServerLoadingView() }
            }
            .onAppear {
                guard let currentUser = Auth.auth().currentUser else { return }
                
                let uid = currentUser.uid
                let cached = UserDefaults.standard.string(forKey: "apple.displayName.\(uid)")
                let display = currentUser.displayName ?? cached
                let email = currentUser.email ?? ""
                
                // Pick best available name: displayName -> cached -> email local-part -> "Player"
                let fallbackName: String = {
                    if let d = display, !d.trimmingCharacters(in: .whitespaces).isEmpty {
                        return d
                    } else if !email.isEmpty, let nick = email.split(separator: "@").first {
                        return String(nick)
                    } else {
                        return "Player"
                    }
                }()
                
                // Split to given/last for your model
                let parts = fallbackName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                let givenName = parts.first.map(String.init) ?? fallbackName
                let lastName  = parts.count > 1 ? String(parts[1]) : ""
                
                loginHaneler.model = .init(givenName: givenName,
                                           lastName: lastName,
                                           email: email)
                Task.detached(priority: .high) {
                    await refreshWordZapPlaces(email: email)
                    await login.changeLanguage(email: email)
                    let gender = await login.gender(email: email)
                    await MainActor.run { loginHaneler.model?.gender = gender }
                }
            }
            .onDisappear { tooltipPusher.stop() }
            .onChange(of: loginHaneler.model) {
                guard loginHaneler.model == nil else { return }
                Task(priority: .userInitiated) { await router.popToRoot() }
            }
            .onChange(of: loginHaneler.model?.gender) {
                guard loginHaneler.model?.gender != nil else { return }
                deepLink(url: deepLinkUrl)
                deepLinkUrl = nil
            }
            .onChange(of: local.locale) {
                guard let email = loginHaneler.model?.email else { return }
                Task.detached(priority: .high) { await login.changeLanguage(email: email) }
            }
            .task { await vm.bootstrap() }
            .onOpenURL { url in
                if GIDSignIn.sharedInstance.handle(url) { return }
                guard loginHaneler.model?.gender != nil else { deepLinkUrl = url; return  }
                deepLink(url: url)
            }
        }
        .environmentObject(router)
        .environmentObject(screenManager)
        .environmentObject(audio)
        .environmentObject(persistenceController)
        .environmentObject(loginHaneler)
        .environmentObject(local)
        .environment(\.locale, local.locale)
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
    }
    
    private func deepLink(url: URL?) {
        guard let url else { return }
        Task(priority: .userInitiated) {
            await router.popToRoot()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                switch url.absoluteString {
                case let absoluteString where absoluteString.contains("home"): break
                case let absoluteString where absoluteString.contains("settings"): router.navigateTo(.settings)
                case let absoluteString where absoluteString.contains("scoreboard"): router.navigateTo(.score)
                case let absoluteString where absoluteString.contains("ai"):   router.navigateTo(.game(diffculty: .ai))
                case let absoluteString where absoluteString.contains("difficulty"):
                    let comp = absoluteString.components(separatedBy: "=")
                    switch comp.last {
                    case "easy":   router.navigateTo(.game(diffculty: .easy))
                    case "medium": router.navigateTo(.game(diffculty: .medium))
                    case "hard":   router.navigateTo(.game(diffculty: .hard))
                    default: break
                    }
                default: break
                }
            }
        }
    }
}
