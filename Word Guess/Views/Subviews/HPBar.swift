//
//  HPBar.swift
//  WordZap
//
//  Created by Barak Ben Hur on 27/08/2025.
//

import SwiftUI

public struct HPBar: View {
    public enum Direction { case leftToRight, rightToLeft }

    // MARK: - Public API
    public var value: Double
    public var maxValue: Double
    public var height: CGFloat
    public var cornerRadius: CGFloat
    public var direction: Direction

    // New: segments + in-bar label
    public var showSegments: Bool
    public var segments: Int
    public var showInBarLabel: Bool

    // Internal states (animations)
    @State private var smoothValue: Double
    @State private var damageValue: Double
    @State private var flashAlpha: Double = 0

    public init(
        value: Double,
        maxValue: Double = 100,
        height: CGFloat = 16,
        cornerRadius: CGFloat = 8,
        direction: Direction = .leftToRight,
        showSegments: Bool = true,
        segments: Int = 10,
        showInBarLabel: Bool = true
    ) {
        self.value = value
        self.maxValue = max(1, maxValue)
        self.height = height
        self.cornerRadius = cornerRadius
        self.direction = direction
        self.showSegments = showSegments
        self.segments = max(1, segments)
        self.showInBarLabel = showInBarLabel
        _smoothValue = State(initialValue: min(max(value, 0), maxValue))
        _damageValue = State(initialValue: min(max(value, 0), maxValue))
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            // Track
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(height: height)

            // Damage trail
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(trailColor)
                    .frame(width: geo.size.width * damageRatio, height: height)
                    .animation(.easeOut(duration: 0.6), value: damageRatio)
                    .allowsHitTesting(false)
                    .modifier(FlipIfRTL(direction: direction))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(height: height)

            // Current HP fill
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [barColor(opacity: 0.95), barColor().opacity(0.75)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * smoothRatio, height: height)
                    .animation(.easeOut(duration: 0.25), value: smoothRatio)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .allowsHitTesting(false)
                    .modifier(FlipIfRTL(direction: direction))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(height: height)

            // New: Segments overlay
            if showSegments {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let count = segments
                    Path { path in
                        for i in 1..<count {
                            let x = CGFloat(i) / CGFloat(count) * w
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: h))
                        }
                    }
                    .stroke(Color.white.opacity(0.18), lineWidth: 1 / UIScreen.main.scale)
                    .blendMode(.overlay)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(height: height)
                .allowsHitTesting(false)
            }

            // New: In-bar label
            if showInBarLabel {
                GeometryReader { geo in
                    Text(labelText)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(inBarTextColor)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .frame(height: height)
                .allowsHitTesting(false)
            }

            // Damage flash
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(flashAlpha))
                .frame(height: height)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: value) { _, new in
            let clamped = min(max(new, 0), maxValue)
            if clamped < smoothValue {
                withAnimation(.easeOut(duration: 0.22)) { smoothValue = clamped }
                withAnimation(.easeOut(duration: 0.6).delay(0.15)) { damageValue = clamped }
                flash()
            } else if clamped > smoothValue {
                withAnimation(.easeOut(duration: 0.35)) { smoothValue = clamped }
                withAnimation(.easeOut(duration: 0.2)) { damageValue = clamped }
            }
        }
        .accessibilityLabel("Health")
        .accessibilityValue(labelText)
    }

    // MARK: - Computed
    private var smoothRatio: CGFloat { CGFloat(min(max(smoothValue / maxValue, 0), 1)) }
    private var damageRatio: CGFloat { CGFloat(min(max(damageValue / maxValue, 0), 1)) }
    private var pct: Double { max(0, min(value / maxValue, 1)) }
    private var labelText: String { "\("HP".localized) \(Int(value))/\(Int(maxValue))" }

    private var inBarTextColor: Color {
        pct >= 0.45 ? .white : .primary
    }

    // MARK: - Colors
    private func barColor(opacity: Double = 1) -> Color {
        switch pct {
        case 0.8...:       return Color(hue: 0.33, saturation: 0.75, brightness: 0.95, opacity: opacity) // green
        case 0.4..<0.8:   return Color(hue: 0.12, saturation: 0.85, brightness: 0.95, opacity: opacity) // yellow/orange
        default:           return Color(hue: 0.0,  saturation: 0.85, brightness: 0.95, opacity: opacity) // red
        }
    }
    private var trailColor: Color { Color.orange.opacity(0.45) }

    private func flash() {
        flashAlpha = 0.35
        withAnimation(.easeOut(duration: 0.18)) { flashAlpha = 0 }
    }
}

// Flip content for RTL fill direction
private struct FlipIfRTL: ViewModifier {
    let direction: HPBar.Direction
    func body(content: Content) -> some View {
        switch direction {
        case .leftToRight: content
        case .rightToLeft: content.scaleEffect(x: -1, y: 1, anchor: .center)
        }
    }
}

// MARK: - Demo
struct HPBarDemo: View {
    @State private var hp: Double = 76
    var body: some View {
        VStack(spacing: 18) {
            HPBar(
                value: hp,
                maxValue: 100,
                height: 20,
                cornerRadius: 10,
                direction: .leftToRight,
                showSegments: true,   // ← 1) טיקים
                segments: 12,
                showInBarLabel: true  // ← 2) טקסט בתוך הפס
            )

            HStack {
                Button("Damage -12") { hp = max(0, hp - 12) }
                Button("Heal +8") { hp = min(100, hp + 8) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

#Preview {
    HPBarDemo()
}
