//
//  AppDelegate.swift
//  TaxiShare_MVP  (WordZap silent-push ready)
//  Created by Barak Ben Hur on 08/08/2024.
//

import SwiftUI
import FacebookLogin
import FirebaseCore
import FirebaseAuth
import GoogleMobileAds
import AVFAudio
import UserNotifications
import WidgetKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Add with your other public callbacks
    var backgroundCompletionHandler: (() -> Void)?
    
    
    // MARK: - Launch
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
            // Facebook SDK
            ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
            
            // Notifications (alerts/badges/sounds) — not strictly needed for *silent* pushes,
            // but harmless if you also use visible notifications.
            let open = UNNotificationAction(identifier: "OPEN_ACTION",
                                            title: "Open",
                                            options: [.foreground])
            let cat = UNNotificationCategory(identifier: "OPEN_DEEPLINK",
                                             actions: [open],
                                             intentIdentifiers: [],
                                             options: [])
            UNUserNotificationCenter.current().setNotificationCategories([cat])
            
            // Set delegate EARLY so cold-start taps are delivered here
            UNUserNotificationCenter.current().delegate = self
            
            // Firebase
            FirebaseApp.configure()
            
            // Register for APNs (needed for silent background pushes)
            application.registerForRemoteNotifications()
            
            // AdMob
            GADMobileAds.sharedInstance().start(completionHandler: nil)
            GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [
                "b1f8623026df56ee0408eaae157025db",
                "bb89a5de06dcfb7fad22837648455185",
                "c76030813578328369b797a6939baf04",
                "81828a9b4a72c815a5432c31e7b5230c",
                "c5e20a9be39006f4bc5e0da60ed271e4"
            ]
            
            dumpBGConfig()
            
            Task(priority: .utility) { await performWordZapRefresh(deeper: true) }
            
            registerBGTasks()
            dumpBGConfig()
            Task(priority: .background) { await scheduleBGWork(reason: "launch") }
            
            return true
        }
    
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void) {
            BackgroundDownloadCenter.shared.reconnectSession(withIdentifier: identifier)
            BackgroundDownloadCenter.shared.backgroundCompletionHandler = completionHandler
        }
    
    // MARK: - URL Opens (FB / Firebase)
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
            ApplicationDelegate.shared.application(
                app,
                open: url,
                sourceApplication: options[.sourceApplication] as? String,
                annotation: options[.annotation]
            )
            return Auth.auth().canHandle(url)
        }
    
    // MARK: - APNs Registration
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            // Let Firebase know (if you use Firebase Messaging for other flows)
#if DEBUG
            let env = "sandbox"
            Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
#else
            let env = "prod"
            Auth.auth().setAPNSToken(deviceToken, type: .prod)
#endif
            
            // Convert to hex string & send to your server (to trigger silent pushes later)
            let token = deviceToken.map { String(format: "%02x", $0) }.joined()
            
            Task {
                guard let uniqe = Auth.auth().currentUser?.uid else { return }
                await Network.DeviceTokenService.register(uniqe: uniqe, token: token, environment: env, userId: Auth.auth().currentUser?.uid)
            }
        }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs registration failed:", error)
    }
    
    // MARK: - Silent Push → Pull fresh data → Update widget/UI
    // This is invoked when a *background* push with aps.content-available=1 arrives.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
            // Example server payload:
            // { aps: { "content-available": 1 }, type: "wordzap.refresh" }
            let type = (userInfo["type"] as? String) ?? ""
            guard type == "wordzap.refresh" else {
                // Let Firebase handle Auth OOB codes etc., if any:
                if Auth.auth().canHandleNotification(userInfo) { completionHandler(.noData) }
                else { completionHandler(.noData) }
                return
            }
            
            // Give ourselves background time, then fetch & refresh.
            let bgID = application.beginBackgroundTask(withName: "wordzap.silentpull")
            Task {
                defer { application.endBackgroundTask(bgID) }
                let changed = await performWordZapRefresh(deeper: false)
                await MainActor.run { SharedStore.requestWidgetReload() }
                completionHandler(changed ? .newData : .noData)
            }
        }
    
    final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
        
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            
            let req = notification.request
            let id  = req.identifier
            let cat = req.content.categoryIdentifier
            let kind = req.content.userInfo["kind"] as? String
            
            // Treat any of these as the daily inactivity reminder
            let isDailyInactivity =
            id.hasPrefix("com.wordzap.dailyInactivity") ||    // identifier strategy
            cat == "DailyInactivity" ||                        // category strategy (define one if you like)
            kind == "DailyInactivityReminder"                  // userInfo strategy (your current method)
            
            if isDailyInactivity {
                // Suppress completely while foreground
                completionHandler([])        // no banner/sound/badge/list
                return
            }
            
            // For everything else (e.g., resume game), choose what you want in-foreground:
            // .banner shows a heads-up while foreground; .list adds to Notification Center without a banner.
            // If you want to suppress everything in-foreground, return [] here too.
            completionHandler([.banner, .sound])   // or [.list] for quiet delivery, or []
        }
    }
    
    // <-- This is called when the user taps the notification (or an action)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo[NotifKeys.deeplink] as? String,
           let url = URL(string: s) {
            Task { await DeepLinkInbox.shared.push(url) }
        }
        completion()
    }
    
    // Optional: if you also post visible notifications while foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            return [.banner, .sound] // or [.banner, .sound] if you want to show while app is open
        }
    
    // MARK: - Graceful background finish for your own triggers
    func sceneDidEnterBackground(_ scene: UIScene) {
        Task(priority: .background) { await scheduleBGWork(reason: "didEnterBackground") }
        let bgID = UIApplication.shared.beginBackgroundTask(withName: "wordzap.graceful")
        Task {
            defer { UIApplication.shared.endBackgroundTask(bgID) }
            guard let uniqe = Auth.auth().currentUser?.uid else { return }
            await refreshWordZapPlaces(uniqe: uniqe)
            await MainActor.run { SharedStore.requestWidgetReload() }
        }
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) { Task { await performWordZapRefresh(deeper: false) } }
}
