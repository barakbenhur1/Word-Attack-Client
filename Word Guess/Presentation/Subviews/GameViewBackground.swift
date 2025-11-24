//
//  BaseGameView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 17/09/2025.
//

import SwiftUI

struct GameViewBackground: View {
    @Environment(\.colorScheme) private var scheme
    
    var body: some View { background() }
    
    @ViewBuilder private func background() -> some View {
        ZStack {
            // Base brand gradient (adaptive)
            LinearGradient(
                colors: baseGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Soft color wash (adaptive opacities)
            AngularGradient(
                gradient: Gradient(colors: washColors),
                center: .center
            )
            .blendMode(scheme == .dark ? .screen : .plusLighter) // softer lift in light mode
            .blur(radius: scheme == .dark ? 22 : 28)
            .opacity(scheme == .dark ? 0.9 : 0.45)
            
            // Vignette (subtle in light mode)
            vignette
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.25), value: scheme) // smooth transition on mode change
        .ignoresSafeArea()
    }
    
    // MARK: - Palettes
    
    private var baseGradient: [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.06, green: 0.08, blue: 0.12),
                Color(red: 0.09, green: 0.10, blue: 0.18),
                Color(red: 0.12, green: 0.10, blue: 0.22)
            ]
        } else {
            // Soft, airy neutrals with a hint of brand hue
            return [
                Color(red: 0.96, green: 0.97, blue: 0.99),
                Color(red: 0.94, green: 0.97, blue: 1.00),
                Color(red: 0.98, green: 0.96, blue: 1.00)
            ]
        }
    }
    
    private var washColors: [Color] {
        if scheme == .dark {
            return [
                .purple.opacity(0.18),
                .cyan.opacity(0.14),
                .pink.opacity(0.16),
                .mint.opacity(0.14),
                .purple.opacity(0.18)
            ]
        } else {
            // Lighter tints for light mode to avoid over-saturation
            return [
                .purple.opacity(0.10),
                .cyan.opacity(0.08),
                .pink.opacity(0.09),
                .mint.opacity(0.08),
                .purple.opacity(0.10)
            ]
        }
    }
    
    private var vignette: some View {
        Group {
            if scheme == .dark {
                // Gentle dark vignette
                RadialGradient(
                    colors: [.clear, .black.opacity(0.28)],
                    center: .center, startRadius: 0, endRadius: 1200
                )
            } else {
                // Light mode: slight edge shading to focus content without dulling whites
                RadialGradient(
                    colors: [.clear, .black.opacity(0.08)],
                    center: .center, startRadius: 0, endRadius: 1200
                )
                .blendMode(.multiply)
            }
        }
    }
}
