//
//  AppStateViewModel.swift
//  Word Guess
//

import Foundation

@MainActor
final class AppStateViewModel: ObservableObject {
    @Published var todayPlace: Int?
    @Published var difficulty: Difficulty = .medium

    /// Load initial state
    func bootstrap() async {
        await refreshPlace()
    }

    /// Force refresh using current difficulty
    func refreshPlace() async {
        await refreshPlace(for: difficulty)
    }

    private func refreshPlace(for d: Difficulty) async {
        if let data = SharedStore.readPlacesData() {
            todayPlace = data.place(for: d)
        } else {
            todayPlace = nil
        }
    }
}
