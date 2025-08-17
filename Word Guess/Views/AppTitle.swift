//
//  AppTitle.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 21/10/2024.
//

import SwiftUI

struct AppTitle: View {
    private let title = "Word Guess".localized
    
    var body: some View {
        let start = String(title[0..<4])
        let end = String(title[4..<title.count])
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                let array = start.toArray()
                ForEach(.constant(array), id: \.self) { c in
                    if let i = array.firstIndex(of: c.wrappedValue) {
                        ZStack {
                            i == 0 || i == 3 ? CharColor.exactMatch.color : i == 2 ? CharColor.partialMatch.color : CharColor.noMatch.color
                            Text(c.wrappedValue)
                                .font(.largeTitle)
                        }
                        .frame(width: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.black,
                                        lineWidth: 1)
                        )
                    }
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            
            HStack(spacing: 0) {
                let array = end.toArray()
                ForEach(.constant(array), id: \.self) { c in
                    if let i = array.firstIndex(of: c.wrappedValue) {
                        ZStack {
                            i == 1 ? CharColor.exactMatch.color : i == 0 ? CharColor.partialMatch.color : CharColor.noMatch.color
                            Text(c.wrappedValue)
                                .font(.largeTitle)
                        }
                        .frame(width: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.black,
                                        lineWidth: 1)
                        )
                    }
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .scaleEffect(.init(width: 1.4,
                           height: 1.4))
        .fixedSize()
    }
}
