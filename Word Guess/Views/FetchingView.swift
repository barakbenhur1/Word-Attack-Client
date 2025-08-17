//
//  FetchingView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 14/08/2025.
//

import SwiftUI

struct FetchingView<VM: ViewModel>: View {
    @State var vm: VM
    
    var body: some View {
        fetchingView()
    }
    
    @ViewBuilder private func fetchingView() -> some View {
        VStack {
            Spacer()
            if vm.word == .emapty {
                ServerLoadingView(title: "Fetching Word".localized)
            }
            Spacer()
        }
        .offset(y: vm.word == .emapty ? -80 : 340)
        .shadow(radius: 4)
    }
}
