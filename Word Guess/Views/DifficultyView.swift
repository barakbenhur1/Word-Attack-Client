//
//  DifficultyView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI

struct DifficultyButton: Identifiable {
    var id = UUID()
    let type: DifficultyType
}

enum DifficultyType: String, Codable, CaseIterable {
    case ai = "⚔️ AI", easy = "😀 Easy", medium = "😳 Medium", hard = "🥵 Hard", tutorial
    
    init?(stripedRawValue: String) {
        switch stripedRawValue.lowercased() {
        case "easy": self = .easy
        case "medium": self = .medium
        case "hard": self = .hard
        default: return nil
        }
    }
    
    var liveValue: Difficulty {
        switch self {
        case .easy: return .easy
        case .medium: return .medium
        case .hard: return .hard
        default: fatalError()
        }
    }
    
    func getLength() -> Int {
        switch self {
        case .easy, .tutorial:
            return 4
        case .medium, .ai:
            return 5
        case .hard:
            return 6
        }
    }
    
}

struct DifficultyView: View {
    @FetchRequest(sortDescriptors: []) var tutorialItems: FetchedResults<TutorialItem>
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    private var tutorialItem: TutorialItem? { return tutorialItems.first }
    
    private let auth = Authentication()
    
    private let buttons: [DifficultyButton] = [
        .init(type: .easy),
        .init(type: .medium),
        .init(type: .hard),
    ]
    
    private func onAppear() {
        audio.stopAudio(true)
        UIApplication.shared.hideKeyboard()
    }
    
    private func onDisappear() {
        audio.stopAudio(false)
    }
    
    private func task() {
        guard tutorialItem == nil else { return }
        router.navigateTo(.game(diffculty: .tutorial))
    }
    
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
            
            contant()
                .onDisappear { onDisappear() }
                .onAppear { onAppear() }
                .task { task() }
        }
    }
    
    @ViewBuilder private func contant() -> some View {
        ZStack(alignment: .top) {
            VStack {
                topButtons()
                    .padding(.vertical, 10)
                
                buttonList()
            }
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .top) {
            AdView(adUnitID: "TopBanner")
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
        }
        .safeAreaInset(edge: .bottom) {
            AdView(adUnitID: "BottomBanner")
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
        }
    }
    
    @ViewBuilder private func topButtons() -> some View {
        HStack {
            Button {
                Task.detached {
                    await MainActor.run { router.navigateTo(.settings) }
                }
            } label: {
                VStack {
                    Image(systemName: "gear")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                    
                    Text("Settings")
                }
            }
            .foregroundStyle(.black)
            .shadow(radius: 4)
            
            Spacer()
            
            Button { router.navigateTo(.score) }
            label: {
                VStack {
                    Image(systemName: "person.3.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                        .foregroundStyle(.linearGradient(colors: [.red.opacity(0.6),
                                                                  .green.opacity(0.6),
                                                                  .yellow.opacity(0.6)],
                                                         startPoint: .leading,
                                                         endPoint: .trailing))
                        .blendMode(.difference)
                    
                    Text("Scoreboard")
                }
            }
            .foregroundStyle(.black)
            .shadow(radius: 4)
        }
    }
    
    @ViewBuilder private func buttonList() -> some View {
        VStack {
            ZStack {
                LinearGradient(colors: [.white.opacity(0.4),
                                        .gray.opacity(0.1)],
                               startPoint: .topTrailing,
                               endPoint: .bottomLeading)
                .blendMode(.luminosity)
                .blur(radius: 4)
                
                VStack {
                    difficultyButton(type: .ai)
                        .shadow(radius: 4)
                    title()
                        .padding(.top, 8)
                        .padding(.bottom, 15)
                    ForEach(buttons) { button in
                        difficultyButton(type: button.type)
                            .shadow(radius: 4)
                    }
                }
                .padding()
            }
            .clipShape(RoundedRectangle(cornerRadius: 60))
            
            logoutButton()
                .padding(.all, 20)
                .shadow(radius: 4)
        }
    }
    
    @ViewBuilder private func title() -> some View {
        Text("Difficulty")
            .font(.title.bold())
            .shadow(radius: 4)
    }
    
    @ViewBuilder private func difficultyButton(type: DifficultyType) -> some View {
        let style: ElevatedButtonStyle = {
            switch type {
            case .easy: ElevatedButtonStyle(palette: .green)
            case .medium: ElevatedButtonStyle(palette: .amber)
            case .hard: ElevatedButtonStyle(palette: .rose)
            case .ai: ElevatedButtonStyle(palette: .teal)
            default: ElevatedButtonStyle()
            }
        }()
        
        Button {
            Task(priority: .userInitiated) {
                await MainActor.run { router.navigateTo(.game(diffculty: type)) }
            }
        } label: { ElevatedButtonLabel(LocalizedStringKey(type.rawValue)) }
            .buttonStyle(style)
    }
    
    @ViewBuilder private func logoutButton() -> some View {
        Button {
            Task.detached(priority: .userInitiated) {
                await MainActor.run {
                    loginHandeler.model = nil
                    auth.logout()
                }
            }
        } label: { ElevatedButtonLabel(LocalizedStringKey("👋 logout")) }
            .buttonStyle(ElevatedButtonStyle(palette: .slate))
    }
}
