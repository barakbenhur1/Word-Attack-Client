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
            LinearGradient(colors: [.red, .yellow, .green, .blue],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .opacity(0.1)
            .ignoresSafeArea()
            
            contanet()
                .onAppear { if tutorialItem == nil { router.navigateTo(.game(diffculty: .tutorial)) } }
        }
    }
    
    @ViewBuilder private func contanet() -> some View {
        VStack {
            AdView(adUnitID: "TopBanner".toKey())
            ZStack(alignment: .top) {
                topButtons()
                buttonList()
            }
            .padding(.horizontal, 40)
            AdView(adUnitID: "BottomBanner".toKey())
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
            
            Spacer()
            
            Button {
                router.navigateTo(.score)
            } label: {
                VStack {
                    Image(systemName: "person.3.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                    
                    Text("Scoreboard")
                }
            }
            .foregroundStyle(.black)
        }
        .padding(.top, 30)
    }
    
    @ViewBuilder private func buttonList() -> some View {
        VStack {
            Spacer()
            title()
                .padding(.vertical, 6)
            ForEach(buttons) { button in
                difficultyButton(type: button.type)
                    .shadow(radius: 4)
                Spacer()
            }
            logoutButton()
                .shadow(radius: 4)
                .padding(.top, 40)
        }
    }
    
    @ViewBuilder private func title() -> some View {
        Text("Difficulty")
            .font(.title.bold())
            .padding(.top, 80)
    }
    
    @ViewBuilder private func difficultyButton(type: DifficultyType) -> some View {
        Button {
            router.navigateTo(.game(diffculty: type))
        } label: {
            Text(type.rawValue.localized())
                .foregroundStyle(Color.black)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 80))
        .overlay {
            RoundedRectangle(cornerRadius: 80)
                .stroke(.black, lineWidth: 1)
        }
    }
    
    @ViewBuilder private func logoutButton() -> some View {
        Button {
            loginHandeler.model = nil
            auth.logout()
        } label: {
            Text("logout")
                .foregroundStyle(Color.white)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
        .background(.red)
        .clipShape(RoundedRectangle(cornerRadius: 80))
        .padding(.bottom, 40)
    }
}
