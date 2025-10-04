//
//  NotificationManager.swift
//  WordZap
//
//  Created by Barak Ben Hur on 30/09/2025.
//

import Foundation
import UserNotifications

// MARK: - Identifiers

enum LocalNotifID {
    // We keep stable identifiers so we can update/cancel reliably
    static let dailyInactivity = "com.yourapp.dailyInactivity"
    static func resumeGame(id: String) -> String { "com.yourapp.resumeGame.\(id)" }
}

enum NotifCategory {
    static let openDeeplink = "OPEN_DEEPLINK"
}

enum NotifKeys {
    static let deeplink = "deeplink"   // String (URL)
    static let gameID   = "gameID"     // String (optional extra)
}

// MARK: - Manager

struct NotificationManager {
    static let shared = NotificationManager()
    private init() {}
    
    // Ask once at startup or from your settings screen
    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        if granted { print("🔔 Local notifications permission granted.") }
        else { print("⚠️ Local notifications permission NOT granted.") }
        await registerCategories()
    }
    
    // Add the category used for default taps + optional explicit action
    @MainActor
    private func registerCategories() {
        let open = UNNotificationAction(
            identifier: "OPEN_ACTION",
            title: "Open",
            options: [.foreground]
        )
        let cat = UNNotificationCategory(
            identifier: NotifCategory.openDeeplink,
            actions: [open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }
    
    // MARK: - Inactivity (not opened today)
    
    /// Schedules a reminder for *today or tomorrow* at the provided hour/minute.
    /// Call this whenever the app becomes active; it will remove the previous one and create a fresh one.
    /// `deeplink` is where the app should navigate when the user taps the notification.
    func scheduleDailyInactivityReminder(
        hour: Int = 19,
        minute: Int = 0,
        title: String = "Miss you today 👋",
        body: String = "Jump back in and keep your streak!",
        deeplink: String = "wordzap://home?src=notif-inactivity"
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [LocalNotifID.dailyInactivity])
        
        let nextTriggerDate = Self.nextTriggerDate(hour: hour, minute: minute)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nextTriggerDate)
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.threadIdentifier = "daily" // groups in Notification Center
        if #available(iOS 15.0, *) { content.interruptionLevel = .active }
        content.categoryIdentifier = NotifCategory.openDeeplink
        content.userInfo = [NotifKeys.deeplink: deeplink]
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: LocalNotifID.dailyInactivity, content: content, trigger: trigger)
        do { try await center.add(req) } catch { print("❌ scheduleDailyInactivityReminder failed: \(error)") }
    }
    
    /// Cancels today’s inactivity reminder (e.g., when user opened the app).
    func cancelDailyInactivityReminder() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [LocalNotifID.dailyInactivity])
    }
    
    private static func nextTriggerDate(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: now)
        let todayTarget = cal.nextDate(after: start, matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents) ?? now
        if todayTarget > now { return todayTarget }
        return cal.date(byAdding: .day, value: 1, to: todayTarget) ?? todayTarget
    }
    
    // MARK: - Resume Game (left mid-round)
    
    /// Schedule a reminder to resume the unfinished game after a delay.
    /// Call this when the app goes to background and there’s an unfinished round.
    func scheduleResumeGameReminder(
        gameID: String,
        delay: TimeInterval = 60 * 30, // 30 min
        title: String = "Round in progress 🎯",
        body: String = "Come back and finish your round."
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [LocalNotifID.resumeGame(id: gameID)])
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.categoryIdentifier = NotifCategory.openDeeplink
        content.threadIdentifier = "resume.\(gameID)"
        // Deep link to the game screen on tap
        content.userInfo = [
            NotifKeys.deeplink: "wordzap://resume?gameID=\(gameID)&src=notif-resume",
            NotifKeys.gameID: gameID
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(5, delay), repeats: false)
        let req = UNNotificationRequest(identifier: LocalNotifID.resumeGame(id: gameID), content: content, trigger: trigger)
        do { try await center.add(req) } catch { print("❌ scheduleResumeGameReminder failed: \(error)") }
    }
    
    /// Cancel any scheduled resume reminder for a specific game (e.g., when the round finishes or user returns).
    func cancelResumeGameReminder(gameID: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [LocalNotifID.resumeGame(id: gameID)])
    }
    
    // MARK: - Debug helpers (optional)
    
    func dumpPending() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            print("🔔 Pending: \(reqs.count)")
            for r in reqs {
                print(" • \(r.identifier) | category: \(r.content.categoryIdentifier) | userInfo: \(r.content.userInfo)")
            }
        }
    }
}
