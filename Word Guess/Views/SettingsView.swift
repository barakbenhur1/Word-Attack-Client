//
//  SettingsView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 22/10/2024.
//

import SwiftUI

enum SettingsOption: String {
    case language = "language", sound = "sound", ai = "ai"
}

struct SettingsOptionButton: Identifiable {
    var id = UUID()
    let type: SettingsOption
}

struct SettingsView: View {
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    
    @State private var items: [SettingsOptionButton] = [.init(type: .sound),
                                                        .init(type: .ai),
                                                        .init(type: .language)]
    
    @State private var showResetAI: Bool = false
    
    @State private var difficulty = UserDefaults.standard.string(forKey: "aiDifficulty") ?? AIDifficulty.easy.rawValue.name
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    private func action(item: SettingsOptionButton) {
        switch item.type {
        case .language: showLanguage()
        case .sound: audio.isOn.toggle()
        case .ai: showResetAI = true
        }
    }
    
    private func showLanguage() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    
    private func resetAI() {
        difficulty = AIDifficulty.easy.rawValue.name
        UserDefaults.standard.set(nil, forKey: "aiDifficulty")
        UserDefaults.standard.set(nil, forKey: "playerHP")
    }
    
    var body: some View {
        ZStack {
            background()
            VStack {
                topView()
                list()
                AdView(adUnitID: "SettingsBanner")
            }
        }
        .customAlert("Reset AI Difficulty",
                     type: .info,
                     isPresented: $showResetAI,
                     actionText: "OK",
                     cancelButtonText: "Cancel",
                     action: resetAI,
                     message: { Text("Are you sure you want to reset AI difficulty process is unreversible") })
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
            HStack {
                BackButton()
                Spacer()
            }
            .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
            
            Text("Settings")
                .font(.largeTitle)
                .padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
    }
    
    @ViewBuilder private func label(item: SettingsOptionButton) -> some View {
        ZStack {
            switch item.type {
            case .language:
                HStack {
                    Text(item.type.rawValue.localized)
                        .font(.headline)
                        .foregroundStyle(.black)
                    
                    Spacer()
                    
                    Text(language == "he" ? "Hebrew" : "English")
                        .font(.headline)
                        .foregroundStyle(.cyan)
                }
            case .sound:
                Toggle(item.type.rawValue.localized, isOn: $audio.isOn)
                    .font(.headline)
                    .foregroundStyle(.black)
                    .tint(.cyan)
                    .toggleStyle(.switch)
            case .ai:
                HStack {
                    Text(item.type.rawValue.localized)
                        .font(.headline)
                        .foregroundStyle(.black)
                    
                    Text(difficulty.localized)
                        .font(.subheadline)
                        .foregroundStyle(.black)
                    
                    Spacer()
                    
                    Text("Reset Difficulty")
                        .font(.headline)
                        .foregroundStyle(.cyan)
                }
            }
        }
        .padding()
    }
}
