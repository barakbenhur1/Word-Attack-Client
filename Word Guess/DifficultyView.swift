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

enum DifficultyType: String, Codable {
    case easy = "Easy", regular = "Regular", hard = "Hard", tutorial
    
    func getLength() -> Int {
        switch self {
        case .easy, .tutorial:
            return 4
        case .regular:
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
        .init(type: .regular),
        .init(type: .hard),
    ]
    
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
            
            contanet()
                .onAppear {
                    audio.stopAudio(true)
                    guard tutorialItem != nil else { return router.navigateTo(.game(diffculty: .tutorial)) }
                }
                .onDisappear { audio.stopAudio(false)  }
        }
    }
    
    @ViewBuilder private func contanet() -> some View {
        VStack {
            AdView(adUnitID: "TopBanner")
            VStack {
                topButtons()
                    .padding(.vertical, 10)
                buttonList()
            }
            .padding(.horizontal, 20)
            AdView(adUnitID: "BottomBanner")
        }
    }
    
    @ViewBuilder private func topButtons() -> some View {
        HStack {
            Button {
                router.navigateTo(.settings)
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
            
            Button {
                router.navigateTo(.score)
            } label: {
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
                LinearGradient(colors: [.white.opacity(0.4), .gray.opacity(0.1)],
                               startPoint: .topTrailing,
                               endPoint: .bottomLeading)
                .blur(radius: 4)
               
                VStack {
                    title()
                        .padding(.top, 10)
                        .padding(.bottom, 15)
                    ForEach(buttons) { button in
                        difficultyButton(type: button.type)
                            .shadow(radius: 4)
                        Spacer()
                    }
                }
                .padding()
            }
            .clipShape(RoundedRectangle(cornerRadius: 60))
            .shadow(radius: 4)
            
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
        Button {
            router.navigateTo(.game(diffculty: type))
        } label: {
            Text(type.rawValue.localized())
                .foregroundStyle(Color.white)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
        .background {
            switch type {
            case .easy:
                LinearGradient(colors: [.black.opacity(0.9), .green],
                               startPoint: .bottomLeading,
                               endPoint: .topTrailing)
                .blur(radius: 4)
                .opacity(0.6)
            case .regular:
                LinearGradient(colors: [.black.opacity(0.9), .yellow],
                               startPoint: .bottomLeading,
                               endPoint: .topTrailing)
                .blur(radius: 4)
                .opacity(0.6)
            case .hard:
                LinearGradient(colors: [.black.opacity(0.9), .orange],
                               startPoint: .bottomLeading,
                               endPoint: .topTrailing)
                .blur(radius: 4)
                .opacity(0.6)
            default:
                Color.clear
            }
        }
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(.gray, lineWidth: 0.1)
        }
    }
    
    @ViewBuilder private func logoutButton() -> some View {
        Button {
            loginHandeler.model = nil
            auth.logout()
        } label: {
            Text("logout")
                .foregroundStyle(Color.black)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
        .background {
            LinearGradient(colors: [.black.opacity(0.9), .red],
                           startPoint: .bottomLeading,
                           endPoint: .topTrailing)
            .blur(radius: 4)
            .opacity(0.6)
        }
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(.gray, lineWidth: 0.1)
        }
    }
}
