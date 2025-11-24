//
//  SettingsView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 22/10/2024.
//

import SwiftUI

enum SettingsOption: String {
    case language = "language", sound = "sound", ai = "ai", premium = "Premium", share = "Share", update = "Update"
    
    @MainActor var stringValue: String { rawValue.localized }
}

struct SettingsOptionButton: Identifiable, Hashable {
    var id = UUID()
    let type: SettingsOption
}

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var premium: PremiumManager
    @EnvironmentObject private var menuManager: MenuManager
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var checker: AppStoreVersionChecker
    
    @State private var items: [SettingsOptionButton] = []
    
    @State private var showResetAI: Bool = false
    
    
    @State private var showShare: Bool = false
    
    @State private var itemSource: InviteItemSource?
    
    @State private var showPaywall = false
    
    @State private var language: String?
    
    @State private var difficulty: String?
    
    var fromSideMenu = false
    
    private func action(item: SettingsOptionButton) {
        switch item.type {
        case .language: showLanguage()
        case .sound:    audio.isOn.toggle()
        case .ai:       showResetAI = difficulty != nil && difficulty != AIDifficulty.easy.name
        case .premium:  handlePremium()
        case .update:   handleUpdate()
        case .share:    break
        }
    }
    
    private func handleUpdate() {
        guard let url = checker.needUpdate?.url else { return }
        openURL(url)
    }
    
    private func handlePremium() {
        if premium.isPremium { Task(priority: .userInitiated) { await premium.restore() } }
        else { showPaywall = true }
    }
    
    private func showLanguage() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    
    private func resetAI() {
        difficulty = AIDifficulty.easy.name
        UserDefaults.standard.set(AIDifficulty.easy.name, forKey: "aiDifficulty")
        UserDefaults.standard.set(nil, forKey: "playerHP")
        Task(priority: .utility) { await SharedStore.writeAIStatsAsync(.init(name: AIDifficulty.easy.name, imageName: AIDifficulty.easy.image)) }
//        menuManager.refresh()
    }
    
    var body: some View {
        ZStack {
            background()
            VStack {
                topView()
                list()
                AdProvider.adView(id: "SettingsBanner")
            }
        }
        .customAlert("Reset AI Difficulty",
                     type: .info,
                     isPresented: $showResetAI,
                     actionText: "OK",
                     cancelButtonText: "Cancel",
                     action: resetAI,
                     message: { Text("Are you sure you want to reset AI difficulty process is unreversible") })
        .onChange(of: premium.isPremium, menuManager.refresh)
        .fullScreenCover(isPresented: $showPaywall) {
            SubscriptionPaywallView(isPresented: $showPaywall)
        }
        .onAppear {
            difficulty = UserDefaults.standard.string(forKey: "aiDifficulty")
            language = local.locale.identifier.components(separatedBy: "_").first
            
            items = [
                .init(type: .premium),
                .init(type: .sound),
                .init(type: .language),
                .init(type: .ai)
            ]
            
            if checker.needUpdate != nil {
                items.append(.init(type: .update))
            }
            
            items.append(.init(type: .share))
        }
    }
    
    @ViewBuilder private func background() -> some View {
        LinearGradient(colors: [.red,
                                .yellow,
                                .green,
                                .blue],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
        .blur(radius: 4)
        .opacity(0.1)
        .ignoresSafeArea()
    }
    
    @ViewBuilder private func list() -> some View {
        List {
            Group {
                ForEach(items) { item in
                    Button { action(item: item) }
                    label: { label(item: item) }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
    }
    
    @ViewBuilder private func topView() -> some View {
        ZStack {
            if !fromSideMenu {
                HStack {
                    BackButton(action: router.navigateBack)
                    Spacer()
                }
                .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
            }
            
            Text("Settings")
                .font(.largeTitle)
                .padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, fromSideMenu ? 50 : 0)
    }
    
    @ViewBuilder private func label(item: SettingsOptionButton) -> some View {
        ZStack {
            ZStack {
                switch item.type {
                case .premium:
                    HStack {
                        Text(item.type.stringValue.localized)
                            .font(.headline.bold().italic())
                        
                        Spacer()
                        
                        Text(premium.isPremium ? "Restore Purchases" : "Purchase")
                            .font(.headline.bold().italic())
                            .foregroundStyle(Color.premiumPurple)
                    }
                    
                case .language:
                    HStack {
                        Text(item.type.stringValue.localized)
                            .font(.headline)
                        
                        Spacer()
                        
                        Text(language == "he" ? "Hebrew" : "English")
                            .font(.headline)
                            .foregroundStyle(Color.activeSettingColor)
                    }
                    
                case .sound:
                    Toggle(item.type.stringValue.localized, isOn: $audio.isOn)
                        .font(.headline)
                        .tint(.activeSettingColor)
                        .toggleStyle(.switch)
                    
                case .ai:
                    HStack {
                        Text(item.type.stringValue.localized)
                            .font(.headline)
                        
                        Text(difficulty?.localized ?? "Not Discoverd".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .animation(.easeInOut, value: difficulty)
                        
                        Spacer()
                        
                        Text("Reset Difficulty")
                            .font(.headline)
                            .foregroundStyle(difficulty == nil || difficulty == AIDifficulty.easy.name ? Color.disabledSettingColor : Color.activeSettingColor)
                    }
                    
                case .update:
                    if let notice = checker.needUpdate {
                        HStack {
                            Text(item.type.stringValue.localized)
                                .font(.headline.bold().italic())
                            
                            Spacer()
                            
                            Text("Update App To Version \(notice.latest)")
                                .font(.caption.bold().italic())
                                .foregroundStyle(Color.activeSettingColor)
                        }
                    }
                    
                case .share:
                    if let uniqe = loginHandeler.model?.uniqe  {
                        InviteFriendsButton(refUserID: uniqe) { item in
                            itemSource = item
                            showShare = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding()
            if let itemSource, showShare {
                ShareSheet(isPresented: $showShare,
                           itemSource: itemSource,
                           anchorRectInScreen: .zero)
            }
        }
    }
}

extension Color {
    static let activeSettingColor = Color(hue: 0.56, saturation: 0.55, brightness: 0.95)
    static let disabledSettingColor = Color(hue: 0.56, saturation: 0.05, brightness: 0.82)
    static let premiumPurple = Color(UIColor { trait in
        if trait.userInterfaceStyle == .dark { return UIColor(hue: 0.675, saturation: 0.26, brightness: 0.94, alpha: 1) }
        else { return UIColor(red: 0.30, green: 0.29, blue: 0.49, alpha: 1) }
    })
}
