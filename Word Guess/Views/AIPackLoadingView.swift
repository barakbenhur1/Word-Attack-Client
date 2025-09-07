//
//  AIPackLoadingView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 17/08/2025.
//

import SwiftUI
import UIKit

// MARK: - Public View

public struct AIPackLoadingView: View {
    // Copy you can customize
    public var title: String = "Loading AI Model…".localized
    public var messages: [String] = AIPackLoadingView.defaultWarmupMessages
    
    // UX knobs
    public var cycleEvery: TimeInterval = 3         // seconds per status line
    public var orbSize: CGFloat = 88
    public var cornerRadius: CGFloat = 20
    public var showsCancel: Bool = false
    public var onCancel: (() -> Void)? = nil
    
    // Accessibility & environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var appeared = false
    
    // Time anchor for cycling text
    @State private var appearDate: Date = .distantPast
    @State private var colors: [Color] = [
        .red,
        .orange,
        .yellow,
        .green,
    ]
    
    public init(
        title: String = "Loading AI Model…",
        messages: [String] = AIPackLoadingView.defaultWarmupMessages,
        cycleEvery: TimeInterval = 0.25,
        orbSize: CGFloat = 88,
        cornerRadius: CGFloat = 20,
        showsCancel: Bool = true,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title.localized
        self.messages = messages
        self.cycleEvery = max(0, cycleEvery)
        self.orbSize = orbSize
        self.cornerRadius = cornerRadius
        self.showsCancel = showsCancel
        self.onCancel = onCancel
    }
    
    public var body: some View {
        VStack(spacing: -10) {
            // Title + rotating status text
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.titleFill)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                
                ZStack {
                    // Pretty, calm orb
                    WarmupOrb(size: orbSize)
                        .accessibilityHidden(true)
                    
                    let isHE = Locale.current.identifier.components(separatedBy: "_").first == "he"
                    
                    // Crossfade between lines (or static if Reduce Motion)
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSince(appearDate)
                        let i = max(0, Int(floor(t / cycleEvery))) % max(messages.count, 1)
                        Text(messages[i].localized)
                            .font(.system(size: 160, design: .rounded).weight(.thin))
                            .foregroundStyle(colors[i % max(colors.count, 1)].opacity(0.15))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .transition(.opacity)
                            .offset(x: isHE ? 25 : -25, y: -15)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: i)
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // Indeterminate shimmer bar
            //            ShimmerProgressBar(height: 6)
            //                .accessibilityLabel("Model is Loading up")
            
            if showsCancel {
                Button {
                    guard appeared else { return }
                    onCancel?()          // fires only on explicit tap
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(Palette.buttonTint)
                .padding(.top, 15)
                .accessibilityLabel("Cancel")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Palette.cardStroke, lineWidth: 1)
                )
                .shadow(color: Palette.cardShadow, radius: 20, x: 0, y: 12)
        )
        .padding(24)
        .onAppear {
            appeared = true
            appearDate = Date()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        .onDisappear {
            appeared = false
        }
    }
}

// MARK: - Default Copy

public extension AIPackLoadingView {
    static let defaultWarmupMessages: [String] =  [
        "◜   ",
        "   ◝",
        "   ◞",
        "◟   ",
    ]
}

// MARK: - Orb
fileprivate struct WarmupOrb: View {
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private let ringWidth: CGFloat = 3
    private let rotationSpeed: Double = 20
    private let breatheSpeed: Double = 1.0
    
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breathe = reduceMotion ? 0.0 : 0.02 * sin(t * breatheSpeed * 2 * .pi)
            let angle = reduceMotion ? Angle.degrees(0)
            : Angle.degrees((t * rotationSpeed).truncatingRemainder(dividingBy: 360))
            
            ZStack {
                Circle()
                    .fill(Palette.orbCore)
                    .frame(width: size, height: size)
                    .shadow(color: Palette.orbCoreGlow, radius: 18)
                    .shadow(color: Palette.orbCoreGlow.opacity(0.5), radius: 8)
                
                Circle()
                    .strokeBorder(Palette.orbInnerHalo, lineWidth: 1)
                    .frame(width: size - 4, height: size - 4)
            
                RingArcs()
                    .stroke(Palette.orbArcGradient,
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .frame(width: size + 18, height: size + 18)
                    .rotationEffect(angle)
            }
            .scaleEffect(1 + breathe)
            .animation(.linear(duration: 1/60), value: t)
        }
        .frame(width: size + 24, height: size + 24)
        .accessibilityHidden(true)
    }
}


fileprivate struct RingArcs: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let arc: CGFloat = .pi * (42/180)
        let gap: CGFloat = .pi * (78/180)
        var start: CGFloat = -.pi/2
        for _ in 0..<3 {
            p.addArc(center: c, radius: r, startAngle: .radians(start), endAngle: .radians(start + arc), clockwise: false)
            start += arc + gap
        }
        return p
    }
}

// MARK: - Shimmer Progress (indeterminate)

fileprivate struct ShimmerProgressBar: View {
    var height: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height/2, style: .continuous)
                .fill(Palette.progressTrack)
                .frame(height: height)
            
            if reduceMotion {
                // simple fill if reduced motion is on
                RoundedRectangle(cornerRadius: height/2, style: .continuous)
                    .fill(Palette.progressFill)
                    .frame(width: 80, height: height)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let phase = t.remainder(dividingBy: 2.0) / 2.0 // 0..1 every 2s
                    GeometryReader { geo in
                        let w = geo.size.width
                        let bandW = max(100, w * 0.28)
                        let x = (w + bandW) * phase - bandW / 2
                        RoundedRectangle(cornerRadius: height/2, style: .continuous)
                            .fill(Palette.progressFill)
                            .frame(height: height)
                            .overlay(
                                LinearGradient(colors: [
                                    .white.opacity(0.0),
                                    .white.opacity(0.35),
                                    .white.opacity(0.0)
                                ], startPoint: .leading, endPoint: .trailing)
                                .frame(width: bandW)
                                .offset(x: x)
                            )
                    }
                    .frame(height: height)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Palette

enum Palette {
    // Card
    static var cardBackground: some ShapeStyle { .thinMaterial }
    static var cardStroke: Color { Color.white.opacity(0.08) }
    static var cardShadow: Color { Color.black.opacity(0.20) }
    
    // Text
    static var titleFill: Color { Color.primary.opacity(0.82) }
    static var subtitleFill: Color { Color.secondary.opacity(0.72) }
    
    // Button
    static var buttonTint: Color { Color.teal.opacity(0.6) }
    
    // Progress
    static var progressTrack: Color { Color.secondary.opacity(0.20) }
    static var progressFill: Color { Color.accentColor.opacity(0.55) }
    
    // Orb
    static var orbCore: RadialGradient {
        RadialGradient(
            colors: [Color(white: 0.97), Color(white: 0.88)],
            center: .center,
            startRadius: 2,
            endRadius: 60
        )
    }
    static var orbCoreGlow: Color { Color.white.opacity(0.55) }
    static var orbInnerHalo: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.10)],
                       startPoint: .top, endPoint: .bottom)
    }
    static var orbArcGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                Color(hue: 0.62, saturation: 0.10, brightness: 1.0).opacity(0.9),
                Color(hue: 0.78, saturation: 0.10, brightness: 1.0).opacity(0.9),
                Color(hue: 0.40, saturation: 0.10, brightness: 1.0).opacity(0.9),
                Color(hue: 0.62, saturation: 0.10, brightness: 1.0).opacity(0.9)
            ]),
            center: .center
        )
    }
}

// MARK: - Handy overlay

public extension View {
    func modelWarmupOverlay(
        isPresented: Bool,
        title: String = "Loading AI Model…",
        messages: [String] = AIPackLoadingView.defaultWarmupMessages,
        showsCancel: Bool = false,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        ZStack {
            self
            if isPresented {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                    .transition(.opacity)
                AIPackLoadingView(title: title,
                                  messages: messages,
                                  showsCancel: showsCancel,
                                  onCancel: onCancel)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
        // Important: when not presented, don’t intercept input
        .allowsHitTesting(true)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(colors: [Color.black, Color(hue: 0.65, saturation: 0.25, brightness: 0.18)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()
        AIPackLoadingView(showsCancel: true, onCancel: {})
    }
    .preferredColorScheme(.dark)
}
