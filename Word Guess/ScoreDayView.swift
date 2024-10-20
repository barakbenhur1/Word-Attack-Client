//
//  ScoreDayView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 15/10/2024.
//

import SwiftUI

struct ScoreDayView: View {
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    @Binding var item: ScoreDayCell
    
    @State private var currentDiffculty: Int = 0
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(item.title)
                .font(.largeTitle).bold()
                .padding(.bottom, 6)
            
            HStack {
                ForEach(item.diffculties, id: \.self) { diffculty in
                    if let index = item.diffculties.firstIndex(of: diffculty) {
                        Button {
                            withAnimation(.smooth) { currentDiffculty = index }
                        } label: {
                            Text(diffculty)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(currentDiffculty == index ? Color.blue : Color.black)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
            
            ZStack {
                VStack(spacing: 10) {
                    HStack {
                        Text("Place")
                            .font(.headline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text("Name")
                            .font(.headline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text("Score")
                            .font(.headline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text("Number Of Words Answered")
                            .font(.headline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text("Total Number Of Words")
                            .font(.headline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    
                    ZStack { Color.black }
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 10)
                    
                    TableView(diraction: .vertical,
                              items: .constant(item.items.count > currentDiffculty ? [item.items[currentDiffculty]] : []),
                              scrollTo: item.items.firstIndex(where: { cell in return cell.first?.email == loginHandeler.model!.email}),
                              didTap: { _ in })
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)
                .padding(.vertical)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.black, lineWidth: 0.1)
            }
            .shadow(radius: 2)
            .frame(maxHeight: .infinity)
            
        }
        .frame(maxWidth: .infinity)
        .onChange(of: item) { currentDiffculty = 0 }
    }
}
