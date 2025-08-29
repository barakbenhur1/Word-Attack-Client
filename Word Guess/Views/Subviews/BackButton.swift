//
//  BackButton.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 17/08/2025.
//

import SwiftUI
import UIKit

public struct BackButton: View {
    // MARK: Config
    public enum Style { case glass, tinted, plain }
    public enum Size  { case compact, regular, large }

    public var title: LocalizedStringKey? = "Back"
    public var style: Style = .glass
    public var size: Size = .regular
    public var icon: String = "chevron.backward" // RTL-aware SF Symbol
    public var tint: Color = .accentColor
    public var action: (() -> Void)? = nil

    // MARK: Env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: LocalizedStringKey? = "Back",
                style: Style = .glass,
                size: Size = .regular,
                icon: String = "chevron.backward",
                tint: Color = .accentColor,
                action: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.size = size
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    // MARK: Sizing
    private var buttonHeight: CGFloat {
        switch size { case .compact: 30 case .regular: 36 case .large: 44 }
    }
    private var horizontalPad: CGFloat {
        switch size { case .compact: 10 case .regular: 14 case .large: 18 }
    }
    private var iconSize: CGFloat {
        switch size { case .compact: 12 case .regular: 14 case .large: 16 }
    }
    private var font: Font {
        switch size {
        case .compact: return .system(size: 14, weight: .semibold, design: .rounded)
        case .regular: return .system(size: 15, weight: .semibold, design: .rounded)
        case .large:   return .system(size: 17, weight: .semibold, design: .rounded)
        }
    }

    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            (action ?? { dismiss() })()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                if let title {
                    Text(title).font(font)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, horizontalPad)
            .frame(height: buttonHeight)
            .background(backgroundStyle)
            .overlay(borderOverlay)
            .clipShape(Capsule())
            .shadow(color: shadowColor, radius: 16, x: 0, y: 10)
            .contentShape(Rectangle()) // generous hit area
            .accessibilityLabel(title ?? "Back")
            .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(PressEffectStyle(scale: 0.97))
        .padding(.leading, 10)
    }

    // MARK: Styles
    private var foregroundStyle: some ShapeStyle {
        switch style {
        case .glass:  return Color.primary.opacity(0.9)
        case .tinted: return Color.white
        case .plain:  return Color.accentColor
        }
    }

    @ViewBuilder private var backgroundStyle: some View {
        switch style {
        case .glass:
            Capsule()
                .fill(.ultraThinMaterial)
        case .tinted:
            Capsule()
                .fill(tint.gradient)
        case .plain:
            Capsule()
                .fill(Color.clear)
        }
    }

    @ViewBuilder private var borderOverlay: some View {
        switch style {
        case .glass:
            Capsule()
                .strokeBorder(
                    LinearGradient(colors: [
                        Color.white.opacity(0.50),
                        Color.white.opacity(0.12)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        case .tinted:
            Capsule()
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        case .plain:
            EmptyView()
        }
    }

    private var shadowColor: Color {
        switch style {
        case .glass:  return Color.black.opacity(scheme == .dark ? 0.35 : 0.18)
        case .tinted: return tint.opacity(0.35)
        case .plain:  return Color.clear
        }
    }
}

// MARK: - Press effect
fileprivate struct PressEffectStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
