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
    @StateObject private var premium = PremiumManager.shared
    
    @State private var tooltipPusher = PhraseProvider()
    
    private let persistenceController = PersistenceController.shared
    private let loginHaneler = LoginHandeler()
    private let screenManager = ScreenManager.shared
    private let audio = AudioPlayer()
    private let local = LanguageSetting()
    private let router = Router.shared
    private let deepLinker = DeepLinker.shared
    private let login = LoginViewModel()
    private let adProvider = AdProvider()
    
    var body: some Scene {
        WindowGroup {
            RouterView {
                if loginHaneler.model == nil { LoginView() }
                else if loginHaneler.hasGender { DifficultyView() }
                else { ServerLoadingView() }
            }
            .handleBackground()
            .onAppear {
                guard let currentUser = Auth.auth().currentUser,
                      let email = currentUser.email else { return }
                loginHaneler.model = getInfo(for: currentUser)
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
                deepLinker.preform()
            }
            .onChange(of: local.locale) {
                guard let email = loginHaneler.model?.email else { return }
                Task.detached(priority: .high) { await login.changeLanguage(email: email) }
            }
            .task {
                SharedStore.wipeGroupOnFreshInstall()
                await vm.bootstrap()
                await premium.loadProducts()
            }
            .onOpenURL { url in
                deepLinker.set(url: url)
                guard loginHaneler.model?.gender != nil else { return }
                deepLinker.preform()
            }
        }
        .environmentObject(router)
        .environmentObject(screenManager)
        .environmentObject(audio)
        .environmentObject(persistenceController)
        .environmentObject(loginHaneler)
        .environmentObject(local)
        .environmentObject(premium)
        .environmentObject(adProvider)
        .environment(\.locale, local.locale)
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
    }
    
    private func getInfo(for currentUser: User) -> LoginAuthModel {
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
        
        return .init(givenName: givenName,
                     lastName: lastName,
                     email: email)
    }
}

struct BackgroundHandlerModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var premium: PremiumManager
    
    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .inactive, .background:
                    audio.pauseForBackground()
                case .active:
                    audio.resumeIfNeeded()
                    Task(priority: .medium) {
                        await premium.loadProducts()
                    }
                default: break
                }
            }
    }
}

private extension View {
    /// Attach this once (e.g., on your root view) to auto-pause/resume audio on background/foreground.
    func handleBackground() -> some View { modifier(BackgroundHandlerModifier()) }
}

