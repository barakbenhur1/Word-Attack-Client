//
//  Scoreboard.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 15/10/2024.
//

import SwiftUI

struct Scoreboard<VM: ScoreboardViewModel>: View {
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    
    @State private var vm = VM()
    @State private var current: Int = 0
    
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
                ZStack(alignment: .topLeading) {
                    Button {
                        router.navigateBack()
                    } label: {
                        Image(systemName: "\(language == "he" ? "forward" : "backward").end.fill")
                            .resizable()
                            .foregroundStyle(Color.black)
                            .frame(height: 40)
                            .frame(width: 40)
                    }
                    
                    Text("Scoreboard")
                        .font(.system(size: 32))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 20)
                .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
                
                if current < vm.data.count {
                    let day = vm.data[current]
                    let difficulties = day.difficulties.sorted { d1, d2 in return DifficultyType(rawValue: d1.value)!.getLength() < DifficultyType(rawValue: d2.value)!.getLength() }
                    
                    let diffcultiesTitles = difficulties.map { $0.value }
                    let items = difficulties.map {
                        let totalNumberOfWords = $0.words.count
                        let members = $0.members.sorted { m1, m2 in m1.totalScore > m2.totalScore }
                        return members.map { ScoreboardCell(email: $0.email,
                                                            name: $0.name,
                                                            score: "\($0.totalScore)",
                                                            numberOfWords: "\($0.words.count - 1)",
                                                            totalNumberOfWords: "\(totalNumberOfWords - 2)")
                        }
                    }
                    
                    let cell: ScoreDayCell =
                        .init(title: day.value,
                              diffculties: diffcultiesTitles,
                              items: items)
                    
                    ZStack(alignment: .top) {
                        ScoreDayView(item: .constant(cell))
                        
                        if !cell.title.isEmpty {
                            HStack {
                                Button {
                                    guard language != "he" ? current < vm.data.count : current > 0 else { return }
                                    if language != "he" { withAnimation(.smooth) { current += 1 } }
                                    else { withAnimation(.smooth) { current -= 1 } }
                                } label: {
                                    Text("->")
                                        .foregroundStyle((language != "he" ? current < vm.data.count - 1 : current > 0) ? .black : .gray)
                                        .font(.largeTitle).fontWeight(.medium)
                                }
                                .disabled(language != "he" ? current == vm.data.count - 1 : current == 0)
                                .padding(.leading, 60)
                                
                                Spacer()
                                
                                Button {
                                    guard language != "he" ? current > 0 : current < vm.data.count - 1 else { return }
                                    if language != "he" { withAnimation(.smooth) { current -= 1 } }
                                    else { withAnimation(.smooth) { current += 1 } }
                                } label: {
                                    Text("<-")
                                        .foregroundStyle((language != "he" ? current > 0 : current < vm.data.count - 1) ? .black : .gray)
                                        .font(.largeTitle).fontWeight(.medium)
                                }
                                .disabled(language != "he" ? current == 0 : current == vm.data.count - 1)
                                .padding(.trailing, 60)
                            }
                            .environment(\.layoutDirection, .rightToLeft)
                        }
                    }
                    
                    Spacer()
                }
                else { Spacer() }
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.top, 10)
            .onAppear { Task { await vm.items(email: loginHandeler.model!.email) } }
            .onChange(of: vm.data) { current = vm.data.count - 1 }
        }
    }
}
