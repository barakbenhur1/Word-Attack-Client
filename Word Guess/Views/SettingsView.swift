//
//  SettingsView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 22/10/2024.
//

import SwiftUI

enum SettingsOption: String {
    case language = "language", sound = "sound", ai = "ai", premium = "Premium", share = "Share"
    
    var stringValue: String { rawValue.localized }
}

struct SettingsOptionButton: Identifiable {
    var id = UUID()
    let type: SettingsOption
}

struct SettingsView: View {
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var adProvider: AdProvider
    @EnvironmentObject private var premium: PremiumManager
    @EnvironmentObject private var menuManager: MenuManager
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    @State private var items: [SettingsOptionButton] = [.init(type: .premium),
                                                        .init(type: .sound),
                                                        .init(type: .ai),
                                                        .init(type: .language),
                                                        .init(type: .share)]
    
    @State private var showResetAI: Bool = false
    
    
    @State private var showShare: Bool = false
    
    @State private var itemSource: InviteItemSource?
    
    @State private var showPaywall = false
    
    @State private var language: String?
    
    @State private var difficulty: String? = UserDefaults.standard.string(forKey: "aiDifficulty")
    
    var fromSideMenu = false
    
    private func action(item: SettingsOptionButton) {
        switch item.type {
        case .language: showLanguage()
        case .sound:    audio.isOn.toggle()
        case .ai:       showResetAI = difficulty != nil
        case .premium:  handlePremium()
        case .share:    break
        }
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
                adProvider.adView(id: "SettingsBanner")
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
    }
    
    @ViewBuilder private func label(item: SettingsOptionButton) -> some View {
        ZStack {
            switch item.type {
            case .premium:
                HStack {
                    Text(item.type.stringValue.localized)
                        .font(.headline.bold().italic())
                        .foregroundStyle(.black)
                    
                    Spacer()
                    
                    Text(premium.isPremium ? "Restore Purchases" : "Purchase")
                        .font(.headline.bold().italic())
                        .foregroundStyle(Color.premiumPurple)
                }
                
            case .language:
                HStack {
                    Text(item.type.stringValue.localized)
                        .font(.headline)
                        .foregroundStyle(.black)
                    
                    Spacer()
                    
                    Text(language == "he" ? "Hebrew" : "English")
                        .font(.headline)
                        .foregroundStyle(Color.darkTurquoise)
                }
                
            case .sound:
                Toggle(item.type.stringValue.localized, isOn: $audio.isOn)
                    .font(.headline)
                    .foregroundStyle(.black)
                    .tint(.darkTurquoise)
                    .toggleStyle(.switch)
                
            case .ai:
                HStack {
                    Text(item.type.stringValue.localized)
                        .font(.headline)
                        .foregroundStyle(.black)
                    
                    Text(difficulty?.localized ?? (ModelStorage.localHasUsableModels() ? "Not Discoverd".localized : "Not downloaded yet".localized))
                        .font(.subheadline)
                        .foregroundStyle(.black)
                        .animation(.easeInOut, value: difficulty)
                    
                    Spacer()
                    
                    Text("Reset Difficulty")
                        .font(.headline)
                        .foregroundStyle(difficulty == nil ? .gray : .darkTurquoise)
                }
                
            case .share:
                if let email = loginHandeler.model?.email  {
                    InviteFriendsButton(refUserID: email) { item in
                        itemSource = item
                        showShare = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            
            if let itemSource, showShare {
                ShareSheet(isPresented: $showShare,
                           itemSource: itemSource,
                           anchorRectInScreen: .zero)
            }
        }
        .padding()
    }
}

extension Color {
    static let darkTurquoise = Color(red: 0.0, green: 0.81, blue: 0.82)
    static let premiumPurple = Color(red: 0.30, green: 0.29, blue: 0.49)
}
