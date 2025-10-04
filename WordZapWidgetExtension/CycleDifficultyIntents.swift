//
//  CycleDifficultyIntents.swift
//  WordZap
//
//  Created by Barak Ben Hur on 31/08/2025.
//

import AppIntents
import WidgetKit

enum CycleDirection: String, AppEnum, CaseDisplayRepresentable, Codable {
    case next, prev
    
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Direction")
    static var caseDisplayRepresentations: [CycleDirection : DisplayRepresentation] = [
        .next: "Next",
        .prev: "Previous"
    ]
}

// MARK: - AppIntent to cycle difficulty (runs without launching the app)
@available(iOS 17.0, *)
struct CycleDifficultyIntent: AppIntent {
    static var title: LocalizedStringResource = "Cycle Difficulty"
    
    enum Direction: String, AppEnum, Sendable {
        static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Direction")
        case prev
        case next
        
        static var caseDisplayRepresentations: [Self : DisplayRepresentation] = [
            .prev : "Previous",
            .next : "Next"
        ]
    }
    
    @Parameter(title: "Direction")
    var direction: Direction
    
    init() {}
    init(direction: Direction) { self.direction = direction }
    
    func perform() async throws -> some IntentResult {
        // Read, compute new difficulty, persist, and refresh widgets — all in the app group.
//        let current = await SharedStore.readCurrentDifficultyAsync()
//        let newDiff: Difficulty = (direction == .next) ? current.next() : current.prev()
//        await SharedStore.writeCurrentDifficultyAsync(newDiff)
//        await SharedStore.requestWidgetReload()
        return .result()
    }
}
