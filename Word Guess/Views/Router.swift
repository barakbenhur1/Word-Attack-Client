//
//  Coordinator.swift
//  TaxiShare_MVP
//
//  Created by Barak Ben Hur on 28/06/2024.
//

import SwiftUI

@Observable
class Router: ObservableObject {
    // Contains the possible destinations in our Router
    enum Route: Codable, Hashable {
        case login
        case difficulty
        case settings
        case score
        case game(diffculty: DifficultyType)
    }
    
    var path: NavigationPath = NavigationPath()
    
    private var navigationAnimation: Bool = false {
        didSet {
            UINavigationBar.setAnimationsEnabled(navigationAnimation)
        }
    }
    
    
    // Builds the views
    @ViewBuilder func view(for route: Route) -> some View {
        switch route {
        case .login:
            LoginView()
        case .difficulty:
            DifficultyView()
        case .settings:
            SettingsView()
        case .score:
            Scoreboard()
        case .game(let value):
            switch value {
            case .roguelike:
                AIGameView()
            default:
                GameView(diffculty: value)
            }
        }
    }
    
    // Used by views to navigate to another view
    func navigateTo(_ appRoute: Route) {
        navigationAnimation = appRoute != .game(diffculty: .tutorial)
        path.append(appRoute)
    }
    
    // Used to go back to the previous screen
    func navigateBack() {
        path.removeLast()
    }
}
