//
//  BackgroundHandler.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 30/08/2025.
//

import Foundation
import BackgroundTasks
import WidgetKit
import FirebaseAuth
import UIKit

// MARK: - IDs you also listed in Info.plist (BGTaskSchedulerPermittedIdentifiers)
enum BGIDs {
    static let refresh = "com.barak.wordzap.refresh"   // light fetch
    static let process = "com.barak.wordzap.process"   // heavier work (device only)
}

// MARK: - One-time registration (call at launch, before scheduling)
func registerBGTasks() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: BGIDs.refresh, using: nil) { task in
        guard let t = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
        Task(priority: .background) { await handleAppRefresh(task: t) }
    }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: BGIDs.process, using: nil) { task in
        guard let t = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
        Task(priority: .background) { await handleProcessing(task: t) }
    }
}

// MARK: - Schedule helpers (safe to call at launch + on appDidEnterBackground)
func scheduleBGWork(reason: String = "unspecified") async {
    await MainActor.run {
        // BG refresh must be available (Low Power Mode / user setting can disable it)
        guard UIApplication.shared.backgroundRefreshStatus == .available else {
            print("[BG] background refresh unavailable (\(UIApplication.shared.backgroundRefreshStatus.rawValue))")
            return
        }
        
        // --- Refresh (allowed on simulator & device)
        BGTaskScheduler.shared.getPendingTaskRequests { pending in
            if pending.contains(where: { $0.identifier == BGIDs.refresh }) {
                print("[BG] refresh already pending")
            } else {
                let req = BGAppRefreshTaskRequest(identifier: BGIDs.refresh)
                req.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // ~15 minutes
                do {
                    try BGTaskScheduler.shared.submit(req)
                    print("[BG] ✅ submitted refresh (\(reason)) @ \(req.earliestBeginDate?.description ?? "now")")
                } catch { printBG(error, id: BGIDs.refresh) }
            }
            
            // --- Processing (device only; simulator rejects)
#if !targetEnvironment(simulator)
            if pending.contains(where: { $0.identifier == BGIDs.process }) {
                print("[BG] processing already pending")
            } else {
                let req = BGProcessingTaskRequest(identifier: BGIDs.process)
                req.requiresNetworkConnectivity = true
                req.requiresExternalPower = false
                do {
                    try BGTaskScheduler.shared.submit(req)
                    print("[BG] ✅ submitted processing (\(reason))")
                } catch { printBG(error, id: BGIDs.process) }
            }
#else
            print("[BG] ℹ️ processing not submitted on simulator")
#endif
            
            BGTaskScheduler.shared.getPendingTaskRequests { all in
                let list = all.map { "\($0.identifier)@\( $0.earliestBeginDate?.timeIntervalSinceNow ?? 0 )s" }
                print("[BG] pending:", list)
            }
        }
    }
}

// MARK: - Handlers
func handleAppRefresh(task: BGAppRefreshTask) async {
    print("[BG] 🔔 refresh fired")
    // chain the next run
    await scheduleBGWork(reason: "post-refresh")
    
    let work = Task(priority: .background) {
        await performWordZapRefresh(deeper: false)
    }
    
    task.expirationHandler = {
        print("[BG] refresh expired")
        work.cancel()
    }
    
    Task { @MainActor in
        _ = await work.result
        let ok = !work.isCancelled
        print("[BG] refresh done ok=\(ok)")
        task.setTaskCompleted(success: ok)
        WidgetCenter.shared.reloadTimelines(ofKind: "WordZapWidget")
    }
}

func handleProcessing(task: BGProcessingTask) async {
    print("[BG] 🔔 processing fired")
    await scheduleBGWork(reason: "post-processing")
    
    let work = Task(priority: .utility) {
        await performWordZapRefresh(deeper: true)
    }
    
    task.expirationHandler = {
        print("[BG] processing expired")
        work.cancel()
    }
    
    Task { @MainActor in
        _ = await work.result
        let ok = !work.isCancelled
        print("[BG] processing done ok=\(ok)")
        task.setTaskCompleted(success: ok)
        WidgetCenter.shared.reloadTimelines(ofKind: "WordZapWidget")
    }
}

// MARK: - Core refresh logic used by both handlers
@discardableResult
func performWordZapRefresh(deeper: Bool) async -> Bool {
    // If user not logged-in, still rotate tooltip and refresh widgets
    guard let email = Auth.auth().currentUser?.email else {
        await rotateTooltipLocally()
        await reloadWidgets()
        return false
    }
    
    // 1) Update places (easy/medium/hard)
    await refreshWordZapPlaces(email: email)
    
    // 2) Optional: heavier work when the system granted processing time
    if deeper {
        // add extra fetches if you have any; write using SharedStore.*Async
    }
    
    // 3) Tooltip (local rotation or your server source)
    await rotateTooltipLocally()
    
    // 4) Widgets
    await reloadWidgets()
    return true
}

func refreshWordZapPlaces(email: String) async {
    let provider = ScorePlaceProvider()
    if let places = await provider.getPlaceInLeaderboard(email: email) {
        await SharedStore.writePlacesDataAsync(places)
    }
}

private func rotateTooltipLocally() async {
    let next = PhraseProvider().nextPhrase()
    await SharedStore.writeAITooltipAsync(next)
}

private func reloadWidgets() async {
    await MainActor.run {
        if #available(iOS 17.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "WordZapWidget")
        } else {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// MARK: - Diagnostics
func dumpBGConfig() {
    let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
    let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    print("[BG] bundle id:", Bundle.main.bundleIdentifier ?? "nil")
    print("[BG] plist name:", Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "nil")
    print("[BG] Permitted IDs:", ids)
    print("[BG] UIBackgroundModes:", modes)
}

private func printBG(_ error: Error, id: String) {
    if let e = error as? BGTaskScheduler.Error {
        // .notPermitted(1)  .tooManyPendingTaskRequests(2)  .notAvailable(3)
        print("[BG][ERR] \(id): code=\(e.code.rawValue) \(e)")
    } else {
        print("[BG][ERR] \(id): \(error.localizedDescription)")
    }
}
