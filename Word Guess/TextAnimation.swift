//
//  TextAnimation.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 21/10/2024.
//


import SwiftUI

struct TextAnimation: View {
    @State var text: String
    
    @State private var points: String = ""
    
    private let queue = DispatchQueue.main
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            Text(text)
                .multilineTextAlignment(.trailing)
                .font(.largeTitle)
                .foregroundStyle(.linearGradient(colors: [.black, .black.opacity(0.8), .black.opacity(0.6)],
                                                 startPoint: .leading,
                                                 endPoint: .trailing))
                .frame(maxWidth: .infinity)
                .font(.largeTitle)
                .fixedSize()
            
            Text(points)
                .multilineTextAlignment(.leading)
                .font(.largeTitle)
                .foregroundStyle(.linearGradient(colors: [.black.opacity(0.4), .black.opacity(0.3), .black.opacity(0.2)],
                                                 startPoint: .leading,
                                                 endPoint: .trailing))
                .frame(maxWidth: .infinity)
                .font(.largeTitle)
                .frame(width: 30)
            Spacer()
        }
        .padding(.horizontal, 40)
        .onAppear {
            withAnimation(.smooth(duration: 0.08).repeatForever(autoreverses: true)) {
                points += "..."
            }
        }
    }
}
