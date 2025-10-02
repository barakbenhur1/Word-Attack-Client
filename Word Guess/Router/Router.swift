//
//  Coordinator.swift
//  TaxiShare_MVP
//
//  Created by Barak Ben Hur on 28/06/2024.
//

import SwiftUI

@Observable
class PremiumCoplitionHandler: Singleton {
    var onForceEndPremium: (([[String]]?, Bool) -> Void) = { _, _ in }
}

@Observable
class Router: Singleton {
    // Contains the possible destinations in our Router
    enum Route: Codable, Hashable {
        case login
        case difficulty
        case settings
        case score
        case premiumScore
        case premium(email: String?)
        case premiumGame(word: String, history: [[String]], allowedLetters: String)
        case game(diffculty: DifficultyType)
    }
    
    var path: NavigationPath = NavigationPath()
    
    private var routeQueue: [Route] = []
    
    private var navigationAnimation: Bool = false { didSet { UINavigationBar.setAnimationsEnabled(navigationAnimation) } }
    
    private var lockNavigation: Bool = false
    
    private let timerBridge = HubTimerBridge()
    
    // Builds the views
    @ViewBuilder func view(for route: Route) -> some View {
        switch route {
        case .login:                                           LoginView()
        case .difficulty:                                      DifficultyView()
        case .settings:                                        SettingsView()
        case .score:                                           LeaderboardView()
        case .premiumScore:                                    PremiumLeaderboardView()
        case .game(let value):                                 gameView(value: value)
        case .premium(let email):                              PremiumHubView(email: email).environmentObject(timerBridge)
        case .premiumGame(let word, let history, let allowed): PremiumHubGameView(vm: .init(word: word),
                                                                                  history: history,
                                                                                  allowedLetters: Set(allowed),
                                                                                  onForceEnd: PremiumCoplitionHandler.shared.onForceEndPremium).environmentObject(timerBridge)
        }
    }
    
    @ViewBuilder private func gameView(value: DifficultyType) -> some View {
        switch value {
        case .ai: AIGameView()
        default:  GameView(diffculty: value)
        }
    }
    
    private func handeleNavigationAnimation(for appRoute: Route) {
        switch appRoute {
        case .premiumGame(_, _, _): navigationAnimation = false
        case .game(let diffculty):  navigationAnimation = diffculty != .tutorial
        default:                    navigationAnimation = true
        }
    }
    
    func navigateToSync(_ appRoute: Route) {
        Task(priority: .userInitiated) {
            await MainActor.run {
                navigateTo(appRoute)
            }
        }
    }
    
    // Used by views to navigate to another view
    @MainActor
    func navigateTo(_ appRoute: Route) {
        guard !lockNavigation else { return }
        guard routeQueue.last != appRoute else { return }
        UIApplication.shared.hideKeyboard()
        handeleNavigationAnimation(for: appRoute)
        routeQueue.append(appRoute)
        path.append(appRoute)
        lockNavigation = true
        Task.detached(priority: .high) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run { [weak self] in
                guard let self else { return }
                lockNavigation = false
            }
        }
    }
    
    // Used to go back to the previous screen
    @MainActor
    func navigateBack() {
        guard !path.isEmpty else { return }
        UIApplication.shared.hideKeyboard()
        routeQueue.removeLast()
        path.removeLast()
    }
    
    func popToRoot() async {
        guard !path.isEmpty else { return }
        await UIApplication.shared.hideKeyboard()
        await MainActor.run { routeQueue = []; path.removeLast(path.count) }
    }
}
