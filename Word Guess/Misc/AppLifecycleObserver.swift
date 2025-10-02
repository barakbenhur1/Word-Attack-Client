//
//  AppLifecycleObserver.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 30/09/2025.
//

import SwiftUI
import UserNotifications

struct AppLifecycleObserver: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @AppStorage("lastOpenDay") private var lastOpenDay: String = "" // "yyyy-MM-dd"
    @ObservedObject var session: GameSessionManager
    
    var inactivityHour: Int = 19  // 7pm local
    var inactivityMinute: Int = 0
    
    func body(content: Content) -> some View {
        content
            .onChange(of: phase) { _, newPhase in
                switch newPhase {
                case .active:
                    Task {
                        // Update last open stamp immediately
                        lastOpenDay = Self.todayKey()
                        // Ask permission once; safe to call again
                        try? await NotificationManager.shared.requestAuthorization()
                        // Re-schedule today's inactivity reminder (fires later if user doesn't reopen)
                        await NotificationManager.shared.scheduleDailyInactivityReminder(hour: inactivityHour,
                                                                                         minute: inactivityMinute)
                        // If we returned to the app, cancel any resume reminder for current game
                        if let gid = session.activeGameID {
                            await NotificationManager.shared.cancelResumeGameReminder(gameID: gid)
                        }
                    }
                    
                case .background:
                    Task {
                        // If the user has a game in progress, set a resume reminder
                        if let gid = session.activeGameID {
                            // Example: ping in 30 minutes
                            await NotificationManager.shared.scheduleResumeGameReminder(gameID: gid, delay: 60 * 30)
                        }
                    }
                    
                default:
                    break
                }
            }
    }
    
    private static func todayKey() -> String {
        let df = DateFormatter()
        df.calendar = .current
        df.locale = .current
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}

extension View {
    func attachAppLifecycleObservers(session: GameSessionManager,
                                     inactivityHour: Int = 19,
                                     inactivityMinute: Int = 0) -> some View {
        modifier(AppLifecycleObserver(session: session,
                                      inactivityHour: inactivityHour,
                                      inactivityMinute: inactivityMinute))
    }
}
