//
//  SettingsView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 22/10/2024.
//

import SwiftUI

enum SettingsOption: String {
    case language = "language", sound = "sound"
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
                                                        .init(type: .language)]
    
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
                        Button {
                            router.navigateBack()
                        } label: {
                            Image(systemName: "\(language == "he" ? "forward" : "backward").end.fill")
                                .resizable()
                                .foregroundStyle(Color.black)
                                .frame(height: 40)
                                .frame(width: 40)
                                .padding(.leading, 10)
                                .padding(.top, 10)
                        }
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
                                    Task { await UIApplication.shared.open(url) }
                                case .sound: audio.isOn.toggle()
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
    }
}
