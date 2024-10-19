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
    case easy = "Easy", regular = "Regular", hard = "Hard"
    
    func getLength() -> Int {
        switch self {
        case .easy:
            return 4
        case .regular:
            return 5
        case .hard:
            return 6
        }
    }
}

struct DifficultyView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    private let auth = Authentication()
    
    private let buttons: [DifficultyButton] = [
        .init(type: .easy),
        .init(type: .regular),
        .init(type: .hard),
    ]
    
    var body: some View {
        ZStack(alignment: .top) {
            HStack {
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
            
            VStack(spacing: 40) {
                Spacer()
                Text("Difficulty")
                    .font(.title.bold())
                    .padding(.top, 80)
                
                ForEach(buttons) { button in
                    Button {
                        router.navigateTo(.game(diffculty: button.type))
                    } label: {
                        Text(button.type.rawValue.localized())
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
                
                Spacer()
                
                Button {
                    auth.logout()
                    loginHandeler.model = nil
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
        .padding(.horizontal, 40)
    }
}
