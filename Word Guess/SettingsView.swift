//
//  SettingsView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 22/10/2024.
//

import SwiftUI

enum SettingsOption: String {
    case language = "change language"
}

struct SettingsOptionButton: Identifiable {
    var id = UUID()
    let type: SettingsOption
}

struct SettingsView: View {
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var router: Router
    
    @State private var items: [SettingsOptionButton] = [.init(type: .language)]
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    var body: some View {
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
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 10)
            
            List {
                ForEach(items) { item in
                    Button {
                        switch item.type {
                        case .language:
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            Task { await UIApplication.shared.open(url) }
                        }
                    } label: {
                        Text(item.type.rawValue.localized())
                            .font(.headline)
                            .foregroundStyle(.black)
                    }
                }
            }
        }
    }
}
