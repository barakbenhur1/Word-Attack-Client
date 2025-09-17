//
//  BaseGameView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 17/09/2025.
//

import SwiftUI

struct GameViewBackguard: View {
    var body: some View { background() }
    
    @ViewBuilder private func background() -> some View {
        ZStack {
            // Base brand gradient (dark, elegant)
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.09, green: 0.10, blue: 0.18),
                    Color(red: 0.12, green: 0.10, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Soft color wash that subtly shifts (static here to keep it lightweight)
            AngularGradient(
                gradient: Gradient(colors: [
                    .purple.opacity(0.18),
                    .cyan.opacity(0.14),
                    .pink.opacity(0.16),
                    .mint.opacity(0.14),
                    .purple.opacity(0.18)
                ]),
                center: .center
            )
            .blendMode(.screen)
            .blur(radius: 22)
            .opacity(0.9)

            // Gentle vignette to lift content
            RadialGradient(
                colors: [.clear, .black.opacity(0.28)],
                center: .center, startRadius: 0, endRadius: 1200
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

}
