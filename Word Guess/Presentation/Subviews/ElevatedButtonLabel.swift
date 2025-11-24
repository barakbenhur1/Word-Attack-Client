//
//  ElevatedButtonLabel.swift
//  WordZap
//
//  Created by Barak Ben Hur on 17/08/2025.
//

import SwiftUI
import UIKit

// MARK: - Pretty Elevated ButtonStyle

public struct ElevatedButtonStyle: ButtonStyle {
    public struct Palette {
        public var gradient: LinearGradient
        public var content: Color = .dynamicBlack
        public var shadow: Color  = .black.opacity(0.35)
        
        public init(gradient: LinearGradient, content: Color = .black, shadow: Color = .black.opacity(0.35)) {
            self.gradient = gradient
            self.content = content == .black ? .dynamicBlack : content
            self.shadow = shadow
        }
        
        // Built-ins (✅ with start/end points)
        public static let googleLogin = Palette (
            gradient: LinearGradient(
                colors: [
                    Color(hue: 0.0, saturation: 0.0, brightness: 1.00),
                    Color(hue: 0.0, saturation: 0.0, brightness: 0.96)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        
        public static let googleLoginDark = Palette (
            gradient: LinearGradient(
                colors: [
                    Color(hue: 0.0, saturation: 0.0, brightness: 0.08),  // near black
                    Color(hue: 0.0, saturation: 0.0, brightness: 0.00)   // pure black
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        
        // Built-ins (✅ with start/end points)
        public static let appleLogin = Palette (
            gradient: LinearGradient(
                colors: [
                    Color(hue: 0.0, saturation: 0.0, brightness: 0.65),  // medium gray
                    Color(hue: 0.0, saturation: 0.0, brightness: 0.48)   // darker gray
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        
        public static let clear  = Palette(
            gradient: LinearGradient(
                colors: [
                    .clear,
                    .clear
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        
        public static let teal  = Palette(
            gradient: LinearGradient(
                colors: [
                    Color(hue: 0.52, saturation: 0.42, brightness: 0.70),
                    Color(hue: 0.52, saturation: 0.60, brightness: 0.78)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        
        public static let purple = Palette(
            gradient: LinearGradient(
                colors: [
                    Color(hue: 0.78, saturation: 0.50, brightness: 0.72),
                    Color(hue: 0.78, saturation: 0.78, brightness: 0.68)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        
        public static let green = Palette(
            gradient: LinearGradient(
                colors: [
                    Color(hue: 0.33, saturation: 0.45, brightness: 0.70),
                    Color(hue: 0.33, saturation: 0.65, brightness: 0.78)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        
        public static let amber = Palette(
            gradient: LinearGradient(
                colors: [
                    Color(hue: 0.10, saturation: 0.45, brightness: 0.72),
                    Color(hue: 0.10, saturation: 0.65, brightness: 0.80)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        
        public static let rose = Palette(
            gradient: LinearGradient(
                colors: [
                    Color(hue: 0.98, saturation: 0.45, brightness: 0.72),
                    Color(hue: 0.98, saturation: 0.65, brightness: 0.80)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        
        public static let share = Palette(
            gradient: LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(hue: 0.56, saturation: 0.55, brightness: 0.88), location: 0.00),
                    .init(color: Color(hue: 0.56, saturation: 0.55, brightness: 0.78), location: 0.60),
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        
        public static let slate = Palette(
            gradient: LinearGradient(
                colors: [Color(white: 0.30), Color(white: 0.36)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            content: .dynamicBlack
        )
    }
    
    public var palette: Palette
    public var height: CGFloat = 72
    public var corner: CGFloat = 34
    public var compressScale: CGFloat = 0.985   // press scale
    public var depth: CGFloat = 10              // shadow y-offset
    
    public init(palette: Palette = .clear, height: CGFloat = 92, corner: CGFloat = 34) {
        self.palette = palette
        self.height = height
        self.corner = corner
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        
        configuration.label
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.content)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                Capsule(style: .continuous)
                    .fill(palette.gradient)
                // inner sheen
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.dynamicBlack.opacity(0.30), Color.dynamicBlack.opacity(0.06)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.softLight)
                    )
                // highlight edge
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.dynamicBlack .opacity(0.35), lineWidth: 0.8)
                            .blendMode(.overlay)
                    )
                // layered drop shadows
                    .shadow(color: palette.shadow.opacity(pressed ? 0.10 : 0.28),
                            radius: pressed ? 6 : 18, x: 0, y: pressed ? depth * 0.3 : depth)
                    .shadow(color: palette.shadow.opacity(pressed ? 0.06 : 0.18),
                            radius: pressed ? 3 : 8,  x: 0, y: pressed ? depth * 0.1 : depth * 0.4)
            }
            .scaleEffect(pressed ? compressScale : 1.0)
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.78, blendDuration: 0.1),
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in
                if down { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7) }
            }
    }
}

// MARK: - Label helper (emoji or SF Symbol)

public struct ElevatedButtonLabel: View {
    public var title: LocalizedStringKey
    public var systemImage: String? = nil  // or put emoji directly in title
    public var image: String? = nil  // or put emoji directly in title
    public var alignment: Alignment = .center
    
    public init(_ title: LocalizedStringKey, systemImage: String? = nil, image: String? = nil, alignment: Alignment = .center) {
        self.title = title
        self.systemImage = systemImage
        self.image = image
        self.alignment = alignment
    }
    
    public var body: some View {
        ZStack(alignment: .leading) {
            if let systemImage {
                Image(systemName: systemImage)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.dynamicBlack)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.leading, 10)
            } else if let image {
                Image(image)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.dynamicBlack)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.leading, 10)
            }
            Text(title)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.dynamicBlack)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(40)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}
