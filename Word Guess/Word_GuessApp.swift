//
//  Word_GuessApp.swift
//  WordZap
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI
import FirebaseAuth
import WidgetKit
import GoogleSignIn

@Observable
class LanguageSetting: ObservableObject { var locale = Locale.current }

@main
struct WordGuessApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    
    @StateObject private var vm = AppStateViewModel()
    @StateObject private var premium = PremiumManager.shared
    @StateObject private var session = GameSessionManager()
    @StateObject private var checker = AppStoreVersionChecker()
    
    @State private var tooltipPusher = PhraseProvider()
    @State private var isInvite = false
    
    private let persistenceController = PersistenceController.shared
    private let loginHandeler = LoginHandeler()
    private let screenManager = ScreenManager.shared
    private let audio = AudioPlayer()
    private let local = LanguageSetting()
    private let router = Router.shared
    private let deepLinker = DeepLinker.shared
    private let login = LoginViewModel()

    var body: some Scene {
        WindowGroup {
            RouterView {
                if loginHandeler.model == nil { LoginView() }
                else if loginHandeler.hasGender { DifficultyView() }
                else { ServerLoadingView() }
            }
            .handleBackground()
            .attachAppLifecycleObservers(session: session, inactivityHour: 19)
            .onAppear { onAppear() }
            .onDisappear { tooltipPusher.stop() }
            .onChange(of: loginHandeler.model) {
                guard loginHandeler.model == nil else { return }
                Task(priority: .high) { await router.popToRoot() }
            }
            .onChange(of: loginHandeler.model?.gender) {
                guard loginHandeler.hasGender else { return }
                deepLinker.preform()
                Task { await consumeQueuedDeepLink() }
            }
            .onChange(of: local.locale) {
                guard let uniqe = loginHandeler.model?.uniqe else { return }
                Task.detached(priority: .high) { await login.changeLanguage(uniqe: uniqe) }
            }
            .onChange(of: deepLinker.inviteRef) { newValue in
                isInvite = newValue != nil
            }
            .task {
                SharedStore.wipeGroupOnFreshInstall()
                await vm.bootstrap()
                await premium.loadProducts()
            }
            .onOpenURL { url in
                deepLinker.set(url: url)
                guard loginHandeler.hasGender else { return }
                deepLinker.preform()
            }
            .onReceive(NotificationCenter.default.publisher(for: .DeepLinkOpen)) { note in
                if let url = note.userInfo?["url"] as? URL {
                    deepLinker.set(url: url)
                    guard loginHandeler.hasGender else { return }
                    deepLinker.preform()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await consumeQueuedDeepLink() }
                }
            }
            .task { await consumeQueuedDeepLink() }
            .task { await checker.check() }
            .overlay {
                if !checker.isDismissed {
                    if let need = checker.needUpdate {
                        UpdateOverlayView(
                            latest: need.latest,
                            onUpdate: { UIApplication.shared.open(need.url) },
                            onClose:  { checker.dismiss() }
                        )
                    }
                }
            }
            .glassFullScreen(isPresented: $isInvite) {
                if let ref = deepLinker.inviteRef {
                    InviteJoinView(ref: ref) { _ in
                        deepLinker.inviteRef = nil
                        isInvite = false
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("UNUserNotificationCenterDidReceiveResponse"))) { _ in }
        }
        .environmentObject(router)
        .environmentObject(screenManager)
        .environmentObject(audio)
        .environmentObject(persistenceController)
        .environmentObject(loginHandeler)
        .environmentObject(local)
        .environmentObject(premium)
        .environmentObject(session)
        .environmentObject(checker)
        .environment(\.locale, local.locale)
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
    }
    
    private func onAppear() {
        guard loginHandeler.model == nil else { return }
        guard let currentUser = Auth.auth().currentUser else { return }
        let uniqe = currentUser.uid
        loginHandeler.model = getInfo(for: currentUser)
        Task.detached(priority: .high) {
            guard await login.isLoggedin(uniqe: uniqe) else { await notLoggedin(); return }
            await refreshWordZapPlaces(uniqe: uniqe)
            await login.changeLanguage(uniqe: uniqe)
            await loggedin(uniqe: uniqe)
        }
    }
    
    private func notLoggedin() async {
        await MainActor.run { loginHandeler.model = nil }
    }
    
    private func loggedin(uniqe: String) async {
        let gender = await login.gender(uniqe: uniqe)
        await MainActor.run { loginHandeler.model?.gender = gender }
    }
    
    private func handleUpdate() {
        guard let url = checker.needUpdate?.url else { return }
        openURL(url)
        checker.dismiss()
    }
    
    private func consumeQueuedDeepLink() async {
        guard loginHandeler.hasGender else { return }
        if let url = await DeepLinkInbox.shared.take() {
            deepLinker.set(url: url)
            deepLinker.preform()
        }
    }
    
    private func getInfo(for currentUser: User) -> LoginAuthModel {
        let uid = currentUser.uid
        let cached = UserDefaults.standard.string(forKey: "apple.displayName.\(uid)")
        let display = currentUser.displayName ?? cached
        let email = currentUser.email ?? ""
        let uniqe = currentUser.uid
        
        // Pick best available name: displayName -> cached -> uniqe local-part -> "Player"
        let fallbackName: String = {
            if let d = display, !d.trimmingCharacters(in: .whitespaces).isEmpty {
                return d
            } else if !email.isEmpty, let nick = email.split(separator: "@").first {
                return String(nick)
            } else {
                return "Player"
            }
        }()
        
        // Split to given/last for your model
        let parts = fallbackName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let givenName = parts.first.map(String.init) ?? fallbackName
        let lastName  = parts.count > 1 ? String(parts[1]) : ""
        
        return .init(givenName: givenName,
                     lastName: lastName,
                     uniqe: uniqe,
                     email: email)
    }
}

struct BackgroundHandlerModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var premium: PremiumManager
    
    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .inactive, .background:
                    audio.pauseForBackground()
                case .active:
                    audio.resumeIfNeeded()
                    Task(priority: .medium) {
                        await premium.loadProducts()
                    }
                default: break
                }
            }
    }
}

actor DeepLinkInbox {
    static let shared = DeepLinkInbox()
    private var queued: URL?

    func push(_ url: URL) { queued = url }
    func take() -> URL? { defer { queued = nil }; return queued }
}

private extension View {
    /// Attach this once (e.g., on your root view) to auto-pause/resume audio on background/foreground.
    func handleBackground() -> some View { modifier(BackgroundHandlerModifier()) }
}

struct OverFullScreenPresenter<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let content: Content

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        _isPresented = isPresented
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ parent: UIViewController, context: Context) {
        if isPresented, parent.presentedViewController == nil {
            let host = UIHostingController(rootView:
                content
                    .background(Color.clear)
                    .ignoresSafeArea()
            )
            host.view.backgroundColor = .clear
            host.modalPresentationStyle = .overFullScreen
            host.modalTransitionStyle = .crossDissolve
            parent.present(host, animated: true)
        } else if !isPresented, parent.presentedViewController != nil {
            parent.dismiss(animated: true)
        }
    }
}

extension View {
    func glassFullScreen<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        background(OverFullScreenPresenter(isPresented: isPresented, content: content))
    }
}

extension Notification.Name {
    static let DeepLinkOpen = Notification.Name("DeepLinkOpen")
}
