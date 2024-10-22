//
//  Word_GuessApp.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI
import FirebaseAuth

@Observable
class LanguageSetting: ObservableObject {
    // initialise this from UserDefaults if you like
    var locale = Locale.current
}

@main
struct WordGuessApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    
    private let persistenceController = PersistenceController.shared
    private let loginHaneler = LoginHandeler()
    private let audio = AudioPlayer()
    private let local = LanguageSetting()
    private let router = Router()
    
    var body: some Scene {
        WindowGroup {
            RouterView {
                if loginHaneler.model == nil { LoginView() }
                else { DifficultyView() }
            }
            .environmentObject(loginHaneler)
            .onAppear {
                guard let currentUser = Auth.auth().currentUser else { return }
                guard let givenName = currentUser.displayName else { return }
                guard let email = currentUser.email else { return }
                loginHaneler.model = .init(givenName: givenName,
                                           email: email)
            }
            .onAppear {
                guard let email = loginHaneler.model?.email else { return }
                Task { await LoginViewModel().changeLanguage(email: email) }
            }
            .onChange(of: local.locale) {
                guard let email = loginHaneler.model?.email else { return }
                Task { await LoginViewModel().changeLanguage(email: email) }
            }
        }
        .environmentObject(router)
        .environmentObject(audio)
        .environmentObject(persistenceController)
        .environment(local)
        .environment(\.locale, local.locale)
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
    }
}
