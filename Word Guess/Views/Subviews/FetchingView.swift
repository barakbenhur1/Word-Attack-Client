//
//  FetchingView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 14/08/2025.
//

import SwiftUI

struct FetchingView: View {
    let word: String
    
    var body: some View { fetchingView() }
    
    @ViewBuilder private func fetchingView() -> some View {
        VStack {
            Spacer()
            if word.isEmpty { ServerLoadingView(title: "Fetching Word") }
            Spacer()
        }
    }
}
