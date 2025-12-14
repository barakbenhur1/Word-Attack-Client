//
//  ServerLoadingView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 31/10/2025.
//


import SwiftUI
import Combine

// MARK: - ServerLoadingView (uses glitch instead of opacity)
public struct ServerLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init() {}
    
    public var body: some View {
        content()
            .ignoresSafeArea()
            .ignoresSafeArea(.keyboard)
    }
    
    @ViewBuilder private func content() -> some View {
        ZStack {
            VStack {
                Spacer()
                // Apply the glitch effect here
                AppTitle(animated: true)
                    .glitch(enabled: !reduceMotion, intensity: .medium)
                Spacer()
            }
        }
    }
}

// MARK: - Glitch ViewModifier

/// A performant glitch effect: short randomized bursts with RGB split, jitter and scanlines.
/// - Respects Reduce Motion (no animation if disabled).
/// - Tweak intensity via `.low / .medium / .high`.
public struct GlitchModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    let enabled: Bool
    let intensity: GlitchIntensity
    
    // Runtime state
    @State private var isBursting: Bool = false
    @State private var jitterX: CGFloat = 0
    @State private var jitterY: CGFloat = 0
    @State private var shearX: CGFloat = 0
    @State private var shearY: CGFloat = 0
    @State private var split: CGFloat = 0
    @State private var cancellables = Set<AnyCancellable>()
    
    public func body(content: Content) -> some View {
        // Base content with subtle transform even outside bursts (off when reduce motion)
        let base = content
            .modifier(GlitchTransform(jitterX: jitterX, jitterY: jitterY, shearX: shearX, shearY: shearY))
        
        // Channel splits only when bursting, blended on top
        let layered = ZStack {
            base
            if isBursting {
                content
                    .colorMultiply(.red)
                    .blendMode(.screen)
                    .offset(x: -split)
                    .opacity(0.85)
                content
                    .colorMultiply(.cyan)
                    .blendMode(.screen)
                    .offset(x: split)
                    .opacity(0.85)
                Scanlines(opacity: 0.16)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            }
        }
        .compositingGroup() // keep blend in a single pass
        
        return layered
            .onAppear { start() }
            .onDisappear { stop() }
    }
    
    private func start() {
        guard enabled, !reduceMotion else { return }
        
        // Drive the effect with a couple of timers:
        // 1) A "heartbeat" timer that updates jitter quickly during a burst.
        // 2) A slow timer that randomly toggles bursts on/off to keep it organic.
        
        // Heartbeat (updates ~20 fps while bursting)
        Timer.publish(every: intensity.heartbeatInterval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard isBursting else { return }
                jitterX = .random(in: -intensity.jitterX...intensity.jitterX)
                jitterY = .random(in: -intensity.jitterY...intensity.jitterY)
                shearX  = .random(in: -intensity.shearX...intensity.shearX)
                shearY  = .random(in: -intensity.shearY...intensity.shearY)
                split   = .random(in: 0...intensity.split)
            }
            .store(in: &cancellables)
        
        // Burst scheduler
        Timer.publish(every: intensity.schedulerInterval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                // Randomly enter a short burst (120–280 ms), then auto-exit
                if !isBursting, Int.random(in: 0..<intensity.burstChanceRange) == 0 {
                    isBursting = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int.random(in: 120...280))) {
                        isBursting = false
                        // Reset transforms to avoid lingering offset
                        jitterX = 0; jitterY = 0; shearX = 0; shearY = 0; split = 0
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func stop() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        isBursting = false
        jitterX = 0; jitterY = 0; shearX = 0; shearY = 0; split = 0
    }
}

/// Public API sugar
public extension View {
    func glitch(enabled: Bool = true, intensity: GlitchIntensity = .medium) -> some View {
        modifier(GlitchModifier(enabled: enabled, intensity: intensity))
    }
}

/// Intensity presets
public enum GlitchIntensity {
    case low, medium, high
    
    var jitterX: CGFloat { switch self { case .low: 2; case .medium: 5; case .high: 9 } }
    var jitterY: CGFloat { switch self { case .low: 1; case .medium: 3; case .high: 6 } }
    var shearX: CGFloat  { switch self { case .low: 0.010; case .medium: 0.025; case .high: 0.050 } }
    var shearY: CGFloat  { switch self { case .low: 0.006; case .medium: 0.015; case .high: 0.030 } }
    var split: CGFloat   { switch self { case .low: 1.5; case .medium: 3.5; case .high: 7 } }
    
    /// How often we update values during a burst (seconds)
    var heartbeatInterval: TimeInterval { switch self { case .low: 0.07; case .medium: 0.045; case .high: 0.030 } }
    /// How often we decide whether to start a new burst (seconds)
    var schedulerInterval: TimeInterval { switch self { case .low: 0.45; case .medium: 0.35; case .high: 0.25 } }
    /// Random chance gate for starting a burst (lower = more frequent)
    var burstChanceRange: Int { switch self { case .low: 12; case .medium: 9; case .high: 6 } }
}

// MARK: - Core transform piece (jitter + shear)

private struct GlitchTransform: ViewModifier {
    let jitterX: CGFloat
    let jitterY: CGFloat
    let shearX: CGFloat
    let shearY: CGFloat
    
    func body(content: Content) -> some View {
        content
            // Shear (skew) via CGAffineTransform
            .transformEffect(CGAffineTransform(a: 1, b: shearY, c: shearX, d: 1, tx: 0, ty: 0))
            .offset(x: jitterX, y: jitterY)
            // Slight 3D tilt to sell the effect (very small)
            .rotation3DEffect(.degrees(Double(shearX * 12)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }
}

// MARK: - Scanlines overlay (cheap to draw)

private struct Scanlines: View {
    @State private var phase: CGFloat = 0
    let opacity: Double
    
    var body: some View {
        GeometryReader { proxy in
            Canvas { ctx, size in
                let spacing: CGFloat = 3
                var y = phase.truncatingRemainder(dividingBy: spacing)
                let lineColor = Color.black.opacity(opacity)
                while y < size.height {
                    var path = Path()
                    path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                    ctx.fill(path, with: .color(lineColor))
                    y += spacing
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 3 // scroll lines downward
                }
            }
        }
        .allowsHitTesting(false)
    }
}
