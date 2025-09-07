//
//  Coordinator.swift
//  TaxiShare_MVP
//
//  Created by Barak Ben Hur on 28/06/2024.
//

import SwiftUI

@Observable
class Router: Singleton {
    // Contains the possible destinations in our Router
    enum Route: Codable, Hashable {
        case login
        case difficulty
        case settings
        case score
        case game(diffculty: DifficultyType)
    }
    
    var path: NavigationPath = NavigationPath()
    
    private var navigationAnimation: Bool = false { didSet { UINavigationBar.setAnimationsEnabled(navigationAnimation) } }
    
    private var lockNavigation: Bool = false
    
    // Builds the views
    @ViewBuilder func view(for route: Route) -> some View {
        switch route {
        case .login: LoginView()
        case .difficulty: DifficultyView()
        case .settings: SettingsView()
        case .score: Scoreboard()
        case .game(let value): gameView(value: value)
        }
    }
    
    @ViewBuilder private func gameView(value: DifficultyType) -> some View {
        switch value {
        case .ai: AIGameView()
        default: GameView(diffculty: value)
        }
    }
    
    // Used by views to navigate to another view
    func navigateTo(_ appRoute: Route) {
        guard !lockNavigation else { return }
        UIApplication.shared.hideKeyboard()
        navigationAnimation = appRoute != .game(diffculty: .tutorial)
        path.append(appRoute)
        lockNavigation = true
        Task(priority: .high) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            lockNavigation = false
        }
    }
    
    // Used to go back to the previous screen
    func navigateBack() {
        guard !path.isEmpty else { return }
        UIApplication.shared.hideKeyboard()
        DeepLinker.shared.reset()
        path.removeLast()
    }
    
    func popToRoot() async {
        guard !path.isEmpty else { return }
        await UIApplication.shared.hideKeyboard()
        await MainActor.run { path.removeLast(path.count) }
    }
}
