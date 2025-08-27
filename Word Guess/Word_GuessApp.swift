//
//  Word_GuessApp.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI
import AVFAudio
import FirebaseAuth
import GoogleMobileAds

@Observable
class LanguageSetting: ObservableObject { var locale = Locale.current }

@main
struct WordGuessApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    
    private let persistenceController = PersistenceController.shared
    private let loginHaneler = LoginHandeler()
    private let audio = AudioPlayer()
    private let local = LanguageSetting()
    private let router = Router()
    private let login = LoginViewModel()
    
    init() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [
            "b1f8623026df56ee0408eaae157025db"
        ]
        
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    
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
                    let gender = await login.gender(email: email)
                    await MainActor.run {
                        loginHaneler.model?.gender = gender
                    }
                }
            }
            .onAppear {
                guard let email = loginHaneler.model?.email else { return }
                Task.detached { await LoginViewModel().changeLanguage(email: email) }
            }
            .onChange(of: local.locale) {
                guard let email = loginHaneler.model?.email else { return }
                Task.detached { await LoginViewModel().changeLanguage(email: email) }
            }
        }
        .environmentObject(router)
        .environmentObject(audio)
        .environmentObject(persistenceController)
        .environmentObject(loginHaneler)
        .environment(local)
        .environment(\.locale, local.locale)
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
    }
}
