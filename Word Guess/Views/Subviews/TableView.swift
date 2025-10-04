//
//  TableView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 15/10/2024.
//

import SwiftUI

struct ScoreboardCell: Hashable {
    let email: String
    let name: String
    let score: String
    let numberOfWords: String
    let totalNumberOfWords: String
}

struct ScoreDayCell: Hashable {
    let title: String
    let diffculties: [String]
    var items: [[ScoreboardCell]]
}

struct TableView<Cell: Hashable>: View {
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    enum ScrollDircation {
        case vertical, horizontal
    }
    
    let diraction: ScrollDircation
    @Binding var items: [[Cell]]
    let scrollTo: Int?
    let didTap: (Cell) -> ()
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    var body: some View {
        ScrollViewReader { value in
            ScrollView(diraction == .vertical ? .vertical : .horizontal, showsIndicators: false) {
                ZStack {
                    switch diraction {
                    case .vertical:
                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                            ForEach(items, id: \.self) { item in
                                row(items: item)
                            }
                        }
                    case .horizontal:
                        LazyHGrid(rows: [GridItem(.flexible())]) {
                            ForEach(items, id: \.self) { item in
                                colum(items: item)
                            }
                        }
                    }
                }
                .padding(.all, 1)
            }
            .onAppear {
                UIScrollView.appearance().bounces = false
                guard let scrollTo else { return }
                value.scrollTo(scrollTo)
            }
        }
    }
    
    @ViewBuilder private func getCell(item: Cell) -> some View {
        switch Cell.self {
        case is ScoreboardCell.Type:
            if let item = item as? ScoreboardCell {
                let index = (items as! [[ScoreboardCell]]).firstIndex(of: [item])!
                VStack {
                    ZStack {
                        HStack {
                            Text("\(index + 1)")
                                .multilineTextAlignment(.center)
                                .font(.subheadline.weight(.thin))
                                .padding(.leading, 14)
                                .padding(.trailing, 9)
                                .frame(width: 56)
                            
                            saparator(diraction: .vertical)
                            
                            Text(item.name.initals().lowercased())
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .font(.title2.weight(.medium))
                            
                            Text(item.score)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .font(.headline.weight(.medium))
                            
                            Text(item.numberOfWords)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .font(.headline.weight(.medium))
                            
                            Text(item.totalNumberOfWords)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .font(.headline.weight(.medium))
                        }
                        .padding(.vertical, 14)
                    }
                    .frame(maxWidth: .infinity)
                    .background(item.email == loginHandeler.model?.email ? .yellow.opacity(0.4) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    if index < items.count - 1 { saparator(diraction: .horizontal) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
                .onTapGesture { didTap(item as! Cell) }
            }
            
        default:
            ZStack {}
        }
    }
    
    @ViewBuilder private func saparator(diraction: ScrollDircation) -> some View {
        switch diraction {
        case .vertical:
            ZStack { Color.black }
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .opacity(0.6)
        case .horizontal:
            ZStack { Color.gray }
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .opacity(0.6)
        }
    }
        
    @ViewBuilder private func colum(items: [Cell]) -> some View {
        VStack {
            ForEach(items.reversed(), id: \.self) { item in
                getCell(item: item)
            }
        }
    }
    
    @ViewBuilder private func row(items: [Cell]) -> some View {
        HStack {
            Spacer()
            ForEach(items.reversed(), id: \.self) { item in
                getCell(item: item)
            }
        }
    }
}
