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
    public var cycleEvery: TimeInterval = 3.0        // seconds per status line
    public var orbSize: CGFloat = 100
    public var cornerRadius: CGFloat = 22
    public var showsCancel: Bool = false
    public var onCancel: (() -> Void)? = nil
    
    // Accessibility & environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    
    @State private var appeared = false
    @State private var appearDate: Date = .distantPast
    @State private var enableFancy = true
    @State private var show = false
    
    public init(
        title: String = "Loading AI Model…",
        messages: [String] = AIPackLoadingView.defaultWarmupMessages,
        cycleEvery: TimeInterval = 3.0,
        orbSize: CGFloat = 100,
        cornerRadius: CGFloat = 22,
        showsCancel: Bool = true,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title.localized
        self.messages = messages
        self.cycleEvery = max(0.5, cycleEvery)
        self.orbSize = orbSize
        self.cornerRadius = cornerRadius
        self.showsCancel = showsCancel
        self.onCancel = onCancel
    }
    
    public var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 16) {
                Spacer()
                
                // Title
                Text(title)
                    .font(.system(size: 21, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.titleFill(scheme))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.9)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 14)
                    .padding(.horizontal, 16)
                
                if show {
                    WarmupOrb(size: orbSize, enableSparks: enableFancy)
                        .padding(.top, 2)
                        .transition(.scale.combined(with: .opacity))
                        .opacity(show ? 1 : 0.001)
                } else {
                    WarmupOrbLight(size: orbSize)
                        .accessibilityHidden(true)
                        .padding(.top, 7)
                }
                
                // Playful status ticker (safe indexing)
                StatusTicker(messages: messages,
                             cycleEvery: cycleEvery,
                             appearDate: $appearDate)
                .padding(.top, 2)
                
                if showsCancel {
                    Button {
                        guard let onCancel, appeared else { return }
                        Task { await MainActor.run { onCancel() } }
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.buttonTint)
                    .buttonBorderShape(.capsule)
                    .padding(.bottom, 14)
                    .accessibilityLabel("Cancel")
                }
                
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .padding(20)
        .onAppear {
            // Show immediately
            
            appeared = true
            appearDate = Date()
            
            // Pre-warm haptic to avoid first-use hitch
            let h = UIImpactFeedbackGenerator(style: .soft)
            h.prepare()
            h.impactOccurred()
            
            withAnimation(.spring(duration: 0.3)) {
                show = true
            }
        }
        .onDisappear { appeared = false }
    }
}

// MARK: - Default Copy

public extension AIPackLoadingView {
    static let defaultWarmupMessages: [String] =  [
        //        "Spinning up neurons…",
        //        "Feeding the attention heads…",
        //        "Preheating the matrix…",
        //        "Brewing gradients…",
        //        "Sharpening tokens…"
    ]
}

// MARK: - Status Ticker (fun but subtle, index-safe)

fileprivate struct StatusTicker: View {
    let messages: [String]
    let cycleEvery: TimeInterval
    @Binding var appearDate: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        Group {
            if reduceMotion {
                Text((messages.first ?? "").localized)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Palette.subtitleFill(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else  if !messages.isEmpty{
                TimelineView(.animation) { ctx in
                    // Snapshot to avoid race with external mutations
                    let safeMessages = messages
                    let period = max(0.25, cycleEvery)
                    let t = max(0, ctx.date.timeIntervalSince(appearDate))
                    let i = Int(t / period) % safeMessages.count
                    let phase = (t / period) - floor(t / period) // 0..1 within current
                    
                    Text(safeMessages[i].localized)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Palette.subtitleFill(scheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .opacity(0.65 + 0.35 * sin(.pi * phase))  // tiny breathe on text
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.35), value: i)
                        .shadow(color: .black.opacity(scheme == .dark ? 0.0 : 0.08), radius: 1, y: 1)
                }
            }
        }
        .accessibilityLabel("Status")
    }
}

// MARK: - Orb
fileprivate struct WarmupOrbLight: View {
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

// MARK: - Orb (modern “liquid” look + sparks)

fileprivate struct WarmupOrb: View {
    var size: CGFloat
    var enableSparks: Bool = true
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    
    private var ringWidth: CGFloat { scheme == .dark ? 3 : 4 }
    private let rotationSpeed: Double = 12
    private let breatheSpeed: Double = 0.9
    private let hueSpeed: Double = 0.07
    
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let breathe = reduceMotion ? 0.0 : 0.025 * sin(t * breatheSpeed * 2 * .pi)
            let angle = reduceMotion ? Angle.zero : Angle.degrees((t * rotationSpeed).truncatingRemainder(dividingBy: 360))
            let hue = (sin(t * hueSpeed * 2 * .pi) * 0.5 + 0.5) // 0..1
            
            ZStack {
                // soft liquid core with depth
                Circle()
                    .fill(
                        RadialGradient(colors: [Color.white.opacity(0.98), Color.white.opacity(0.86)],
                                       center: .center, startRadius: 2, endRadius: size * 0.62)
                    )
                    .frame(width: size, height: size)
                    .shadow(color: (scheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.06)),
                            radius: scheme == .dark ? 20 : 10)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(scheme == .dark ? 0.22 : 0.35), lineWidth: 1)
                    )
                
                // rotating chroma band (modern, fun)
                Circle()
                    .trim(from: 0.05, to: 0.95)
                    .stroke(Palette.dynamicSpectrum(huePosition: hue),
                            style: StrokeStyle(lineWidth: ringWidth + 1.5, lineCap: .round))
                    .frame(width: size + 20, height: size + 20)
                    .rotationEffect(angle)
                    .opacity(0.98)
                
                // inner micro rings for parallax
                Circle()
                    .trim(from: 0.0, to: 0.35)
                    .stroke(Palette.dynamicSpectrum(huePosition: hue),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, dash: [4, 7], dashPhase: CGFloat(t * 18)))
                    .frame(width: size - 12, height: size - 12)
                    .opacity(scheme == .dark ? 0.85 : 1.0)
                
                // tiny orbiting sparks (deferred 1 frame for snappier first paint)
                if !reduceMotion && enableSparks {
                    OrbSparks(radius: size * 0.62, hue: hue)
                        .frame(width: size + 28, height: size + 28)
                }
            }
            .scaleEffect(1 + breathe)
            .animation(.linear(duration: 1/60), value: t)
        }
        .frame(width: size + 28, height: size + 28)
        .accessibilityHidden(true)
    }
}

fileprivate struct OrbSparks: View {
    var radius: CGFloat
    var hue: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let count = 6
            
            // Build once per frame, reuse for all sparks
            let gradientColors: [Color] = (0..<10).map { j in
                let off = Double(j) * 0.12
                var h = hue + off
                if h >= 1 { h -= 1 }
                if h < 0  { h += 1 }
                return Color(hue: h, saturation: 0.58, brightness: 1.0)
            }
            let gradient = Gradient(colors: gradientColors)
            
            Canvas { context, size in
                let c = CGPoint(x: size.width/2, y: size.height/2)
                let step = .pi * 2 / CGFloat(count)
                
                for i in 0..<count {
                    let theta = CGFloat(t * 0.9) + step * CGFloat(i)
                    let r = radius + sin(CGFloat(t) + CGFloat(i) * 6) * 4
                    let pt = CGPoint(x: c.x + cos(theta) * r, y: c.y + sin(theta) * r)
                    let sparkSize = 2 + (1 + sin(CGFloat(t) * 2 + CGFloat(i) * 8)) // ~2..4
                    let rect = CGRect(x: pt.x - sparkSize/2, y: pt.y - sparkSize/2,
                                      width: sparkSize, height: sparkSize).integral
                    let shading = GraphicsContext.Shading.conicGradient(gradient, center: pt, angle: .zero)
                    context.fill(Path(ellipseIn: rect), with: shading)
                }
            }
        }
        .opacity(reduceMotion ? 0 : 0.9)
        .allowsHitTesting(false)
    }
}

// MARK: - Decorative “chromatic edge” (subtle modern accent)

fileprivate struct ChromaticEdgeHighlight: View {
    let cornerRadius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.22)
                    ]),
                    center: .center
                ),
                lineWidth: 0.8
            )
            .blendMode(.plusLighter)
    }
}

// MARK: - Palette (scheme-aware)

enum Palette {
    // Card
    static func cardBackground(_ scheme: ColorScheme) -> AnyShapeStyle {
        scheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial)
    }
    static func cardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    static func cardShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.28) : Color.black.opacity(0.20)
    }
    
    // Text
    static func titleFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.88)
    }
    static func subtitleFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.80) : Color.black.opacity(0.65)
    }
    
    // Button
    static var buttonTint: Color { Color(hue: 0.56, saturation: 0.55, brightness: 0.95) }
    
    // Dynamic spectrum for the orb & accents
    static func dynamicSpectrum(huePosition: Double) -> AngularGradient {
        let base = huePosition
        func c(_ off: Double) -> Color {
            let h = (base + off).truncatingRemainder(dividingBy: 1.0)
            return Color(hue: h < 0 ? h + 1 : h, saturation: 0.58, brightness: 1.0)
        }
        return AngularGradient(gradient: Gradient(colors: [
            c(0.00), c(0.12), c(0.24), c(0.36), c(0.48),
            c(0.60), c(0.72), c(0.84), c(0.96), c(1.08)
        ]), center: .center)
    }
    
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
                // soft vignette (slightly stronger in light mode)
                GeometryReader { proxy in
                    let scheme: ColorScheme = (proxy.size.width > 0 && proxy.size.height > 0) ?
                    (UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light) : .light
                    LinearGradient(
                        colors: [
                            Color.black.opacity(scheme == .dark ? 0.28 : 0.35),
                            Color.black.opacity(scheme == .dark ? 0.18 : 0.25)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }
                .transition(.opacity)
                
                AIPackLoadingView(title: title,
                                  messages: messages,
                                  showsCancel: showsCancel,
                                  onCancel: onCancel)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: isPresented)
        .allowsHitTesting(true)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(colors: [
            Color.black,
            Color(hue: 0.65, saturation: 0.26, brightness: 0.20)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()
        
        AIPackLoadingView(showsCancel: true, onCancel: {})
            .padding()
    }
    .preferredColorScheme(.dark)
}
