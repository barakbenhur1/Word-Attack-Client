//
//  SettingsView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 22/10/2024.
//

import SwiftUI

enum SettingsOption: String {
    case language = "language", sound = "sound", clearAI = "ai"
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
                                                        .init(type: .clearAI),
                                                        .init(type: .language)]
    
    @State private var showResetAI: Bool = false
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.red,
                                    .yellow,
                                    .green,
                                    .blue],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .blur(radius: 4)
            .opacity(0.1)
            .ignoresSafeArea()
            
            VStack {
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
                
                List {
                    Group {
                        ForEach(items) { item in
                            Button {
                                switch item.type {
                                case .language:
                                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                    Task { await MainActor.run { UIApplication.shared.open(url) } }
                                case .sound: audio.isOn.toggle()
                                case .clearAI: showResetAI = true
                                }
                            } label: {
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
                                    case .clearAI:
                                        HStack {
                                            Text(item.type.rawValue.localized)
                                                .font(.headline)
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
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .customAlert("Reset AI Difficulty",
                     type: .info,
                     isPresented: $showResetAI,
                     actionText: "OK",
                     cancelButtonText: "Cancel",
                     action: { UserDefaults.standard.set(nil, forKey: "aiDifficulty") },
                     message: { Text("Are you sure you want to reset AI difficulty process is unreversible") })
    }
}
