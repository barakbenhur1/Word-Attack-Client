//
//  SideMenu.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 14/09/2025.
//

import SwiftUI

struct SideMenu<Content: View>: View {
    @Binding var isOpen: Bool
    let width: CGFloat
    let content: Content
    
    init(isOpen: Binding<Bool>, width: CGFloat = 320, @ViewBuilder content: () -> Content) {
        self._isOpen = isOpen
        self.width = width
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Dimmed background
            if isOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { isOpen = false }
                    }
            }
            
            // Side menu content
            HStack {
                content
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .offset(x: isOpen ? 0 : -width)
                    .transition(.move(edge: .leading))
                Spacer()
            }
        }
        .animation(.easeInOut, value: isOpen)
    }
}
