//
//  AppLifecycleObserver.swift
//  WordZap
//
//  Created by Barak Ben Hur on 30/09/2025.
//

import SwiftUI
import UserNotifications

struct AppLifecycleObserver: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @AppStorage("lastOpenDay") private var lastOpenDay: String = "" // "yyyy-MM-dd"
    @ObservedObject var session: GameSessionManager

    var inactivityHour: Int = 19
    var inactivityMinute: Int = 0

    // Debounce: if user bounces back quickly, don't schedule
    private let backgroundGraceSeconds: UInt64 = 3

    func body(content: Content) -> some View {
        content
            .onChange(of: phase) { _, newPhase in
                switch newPhase {
                case .active, .inactive:
                    // Any time we’re foreground-ish, refresh & cancel pending “resume/inactivity”
                    Task {
                        lastOpenDay = Self.todayKey()
                        // Ask once; harmless if already granted, but you can gate it if you prefer
                        try? await NotificationManager.shared.requestAuthorization()

                        await NotificationManager.shared.cancelDailyInactivityReminder()
                        if let gid = session.activeGameID {
                            await NotificationManager.shared.cancelResumeGameReminder(gameID: gid)
                        }
                    }

                case .background:
                    // Only schedule after a brief grace, and only if ALL scenes are background
                    Task {
                        try? await Task.sleep(nanoseconds: backgroundGraceSeconds * 1_000_000_000)

                        // If we returned to foreground during grace, skip
                        if isAnySceneForeground() { return }

                        // Daily inactivity (time-based)
                        await NotificationManager.shared.scheduleDailyInactivityReminder(
                            hour: inactivityHour,
                            minute: inactivityMinute
                        )

                        // Resume game (relative delay) — schedule only if we’re still backgrounded
                        if let gid = session.activeGameID, !isAnySceneForeground() {
                            await NotificationManager.shared.scheduleResumeGameReminder(
                                gameID: gid,
                                delay: 60 * 30
                            )
                        }
                    }

                default:
                    break
                }
            }
    }

    private func isAnySceneForeground() -> Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
    }

    private static func todayKey() -> String {
        let df = DateFormatter()
        df.calendar = .current; df.locale = .current; df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}

// MARK: - Public attach API
extension View {
    func attachAppLifecycleObservers(
        session: GameSessionManager,
        inactivityHour: Int = 19,
        inactivityMinute: Int = 0
    ) -> some View {
        modifier(AppLifecycleObserver(session: session,
                                      inactivityHour: inactivityHour,
                                      inactivityMinute: inactivityMinute))
    }
}
