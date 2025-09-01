//
//  Word_GuessApp.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI
import FirebaseAuth
import WidgetKit

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
                guard let givenName = currentUser.displayName else { return }
                guard let email = currentUser.email else { return }
                loginHaneler.model = .init(givenName: givenName,
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
                guard loginHaneler.model != nil else { return }
                deepLink(url: deepLinkUrl)
                deepLinkUrl = nil
            }
            .onChange(of: local.locale) {
                guard let email = loginHaneler.model?.email else { return }
                Task.detached(priority: .high) { await login.changeLanguage(email: email) }
            }
            .task { await vm.bootstrap() }
            .onOpenURL { url in
                guard loginHaneler.model != nil else { deepLinkUrl = url; return  }
                deepLink(url: url)
            }
        }
        .environmentObject(router)
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
                case "home": break
                case let absoluteString where absoluteString.contains("ai"): router.navigateTo(.game(diffculty: .ai))
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
