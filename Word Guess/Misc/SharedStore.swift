//
//  SharedStore.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 30/08/2025.
//

import Foundation
import WidgetKit

public enum Difficulty: String, Codable, CaseIterable {
    case easy, medium, hard
    
    // Handy helpers if you need cycling elsewhere
    public func next() -> Difficulty {
        switch self { case .easy: return .medium; case .medium: return .hard; case .hard: return .easy }
    }
    public func prev() -> Difficulty {
        switch self { case .easy: return .hard; case .medium: return .easy; case .hard: return .medium }
    }
}

public struct TodayStats: Codable, Equatable {
    public let answers: Int
    public let score: Int
}

public struct AIStats: Codable, Equatable {
    public let name: String
    public let imageName: String?
}

// NOTE: LeaderboaredPlaceData is defined elsewhere in your project.

enum SharedStore {
    static let appGroupID  = "group.com.barak.wordzap"   // ← your real App Group
    
    // Keys
    private static let placesDataKey        = "leaderboard.places.data"
    private static let currentDifficultyKey = "wordzap.widget.currentDifficulty"
    private static let aiTooltipKey         = "ai.tooltip"
    private static let diffStatsKeyPrefix   = "stats.difficulty." // + difficulty.rawValue
    private static let aiStatsKey           = "ai.stats"
    
    // MARK: - Generic helpers
    
    private static func ud() -> UserDefaults? { UserDefaults(suiteName: appGroupID) }
    
    private static func encode<T: Encodable>(_ value: T) async -> Data? {
        await Task.detached(priority: .utility) { try? JSONEncoder().encode(value) }.value
    }
    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) async -> T? {
        await Task.detached(priority: .utility) { try? JSONDecoder().decode(T.self, from: data) }.value
    }
    
    // MARK: - Leaderboard Places (ranks per difficulty) — PLACE ONLY
    
    static func readPlacesData() -> LeaderboaredPlaceData? {
        guard let raw = ud()?.data(forKey: placesDataKey) else { return nil }
        return (try? JSONDecoder().decode(LeaderboaredPlaceData.self, from: raw))
    }
    
    static func readPlacesDataAsync() async -> LeaderboaredPlaceData? {
        let raw: Data? = await MainActor.run { ud()?.data(forKey: placesDataKey) }
        guard let raw else { return nil }
        return await decode(LeaderboaredPlaceData.self, from: raw)
    }
    
    static func writePlacesData(_ data: LeaderboaredPlaceData) {
        if let encoded = try? JSONEncoder().encode(data) {
            ud()?.set(encoded, forKey: placesDataKey)
        }
    }
    
    static func writePlacesDataAsync(_ data: LeaderboaredPlaceData) async {
        let encoded = await encode(data)
        await MainActor.run { ud()?.set(encoded, forKey: placesDataKey) }
    }
    
    // MARK: - Per-difficulty “today” stats (answers/score only — NO place here)
    
    static func readDifficultyStats(for difficulty: Difficulty) -> TodayStats? {
        let key = diffStatsKeyPrefix + difficulty.rawValue
        guard let raw = ud()?.data(forKey: key) else { return nil }
        return (try? JSONDecoder().decode(TodayStats.self, from: raw))
    }
    
    static func readDifficultyStatsAsync(for difficulty: Difficulty) async -> TodayStats? {
        let key = diffStatsKeyPrefix + difficulty.rawValue
        let raw: Data? = await MainActor.run { ud()?.data(forKey: key) }
        guard let raw else { return nil }
        return await decode(TodayStats.self, from: raw)
    }
    
    static func writeDifficultyStats(_ stats: TodayStats, for difficulty: Difficulty) {
        let key = diffStatsKeyPrefix + difficulty.rawValue
        if let encoded = try? JSONEncoder().encode(stats) {
            ud()?.set(encoded, forKey: key)
        }
    }
    
    static func writeDifficultyStatsAsync(_ stats: TodayStats, for difficulty: Difficulty) async {
        let key = diffStatsKeyPrefix + difficulty.rawValue
        let encoded = await encode(stats)
        await MainActor.run { ud()?.set(encoded, forKey: key) }
    }
    
    static func removeDifficultyStats(_ difficulty: Difficulty) {
        ud()?.removeObject(forKey: diffStatsKeyPrefix + difficulty.rawValue)
    }
    
    static func removeDifficultyStatsAsync(_ difficulty: Difficulty) async {
        await MainActor.run { ud()?.removeObject(forKey: diffStatsKeyPrefix + difficulty.rawValue) }
    }
    
    // MARK: - AI Tooltip (text only — kept separate)
    
    static func readAITooltip() -> String? {
        ud()?.string(forKey: aiTooltipKey)
    }
    
    static func readAITooltipAsync() async -> String? {
        await MainActor.run { ud()?.string(forKey: aiTooltipKey) }
    }
    
    static func writeAITooltip(_ text: String?) {
        if let t = text, !t.isEmpty {
            ud()?.set(t, forKey: aiTooltipKey)
        } else {
            ud()?.removeObject(forKey: aiTooltipKey)
        }
    }
    
    static func writeAITooltipAsync(_ text: String?) async {
        await MainActor.run { writeAITooltip(text) }
    }
    
    static func readAIStats() -> AIStats? {
        guard let raw = ud()?.data(forKey: aiStatsKey) else { return nil }
        return try? JSONDecoder().decode(AIStats.self, from: raw)
    }

    static func readAIStatsAsync() async -> AIStats? {
        let raw: Data? = await MainActor.run { ud()?.data(forKey: aiStatsKey) }
        guard let raw else { return nil }
        return try? await Task.detached(priority: .utility) {
            try JSONDecoder().decode(AIStats.self, from: raw)
        }.value
    }

    static func writeAIStats(_ stats: AIStats) {
        if let encoded = try? JSONEncoder().encode(stats) {
            ud()?.set(encoded, forKey: aiStatsKey)
        }
    }

    static func writeAIStatsAsync(_ stats: AIStats) async {
        let encoded = await encode(stats)
        await MainActor.run { ud()?.set(encoded, forKey: aiStatsKey) }
    }
    
    // MARK: - Widget reload
    
    @MainActor
    static func requestWidgetReload() {
        WidgetCenter.shared.reloadTimelines(ofKind: "WordZapWidget")
    }
    
    // MARK: - Date helper
    
    static func todayISO() -> String {
        let f = DateFormatter()
        f.calendar = .init(identifier: .gregorian)
        f.locale   = .init(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// Small util to map only valid pairs from a sequence of (K,V)
private extension Dictionary {
    static func compactMapPairs<S: Sequence>(_ s: S, _ transform: (S.Element) -> (Key, Value)?) -> [Key: Value] {
        var out: [Key: Value] = [:]
        for e in s {
            if let (k, v) = transform(e) { out[k] = v }
        }
        return out
    }
}
