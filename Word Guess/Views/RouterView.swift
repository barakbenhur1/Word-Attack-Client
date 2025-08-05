//
//  RouterView.swift
//  TaxiShare_MVP
//
//  Created by Barak Ben Hur on 28/06/2024.
//

import SwiftUI

struct RouterView<Content: View>: View {
    @EnvironmentObject private var router: Router
    
    // Our root view content
    private let content: Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationBarBackButtonHidden()
                .toolbar(.hidden)
                .navigationDestination(for: Router.Route.self) { route in
                    router.view(for: route)
                        .navigationBarBackButtonHidden()
                        .toolbar(.hidden)
                }
        }
    }
}
