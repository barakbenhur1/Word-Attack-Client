import SwiftUI

struct CenterPinnedBurstModifier: ViewModifier {
    @Binding var trigger: Bool
    
    func body(content: Content) -> some View {
        content
            .mask(Circle())
            .scaleEffect(!trigger ? 0.2 : 3)
            .opacity(trigger ? 1 : 0)
    }
}

struct ElevatedModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var shadowColor: Color = .black.opacity(0.15)
    var shadowRadius: CGFloat = 8
    var shadowYOffset: CGFloat = 4
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius,
                                 style: .continuous)
                .fill(Color.white.opacity(0.4))
                .shadow(color: shadowColor,
                        radius: shadowRadius,
                        x: 0,
                        y: shadowYOffset)
                .shadow(color: .black.opacity(0.05),
                        radius: 2,
                        x: 0,
                        y: 1) // subtle secondary shadow
            )
    }
}

struct RealisticCellModifier: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(gradient: Gradient(colors: [color,
                                                                     color.opacity(0.15)]),
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3),
                        lineWidth: 1))
            .shadow(color: .black.opacity(0.15),
                    radius: 6,
                    x: 3,
                    y: 3)
            .shadow(color: .white.opacity(0.7),
                    radius: 6,
                    x: -3,
                    y: -3) // top-left glow
            .padding(4)
    }
}

import SwiftUI

struct LoadingViewModifier: ViewModifier {
    let show: Bool
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(show)                 // block taps behind the loader
                .blur(radius: show ? 1 : 0)
            
            if show {
                // Dim the whole screen a bit
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                // Big spinner + optional label
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(2.0)       // 👈 make it LARGE
                        .tint(.primary)         // or .white if you prefer
                    
                    // Text("Loading…")
                    //     .font(.headline)
                    //     .foregroundColor(.primary)
                }
                .padding(24)
                .background(.ultraThinMaterial, in:
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .shadow(radius: 12)
                .transition(.scale.combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading")
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: show)
        .zIndex(show ? 1 : 0)
    }
}

struct BrickBorderModifier: ViewModifier {
    var color: Color = .gray
    var lineWidth: CGFloat = 6
    var brickLength: CGFloat = 24
    var gapLength: CGFloat = 8
    var cornerRadius: CGFloat = 8
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        color,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .butt,
                            lineJoin: .miter,
                            dash: [brickLength, gapLength]
                        )
                    )
            )
    }
}

// MARK: - Modifier
private struct RealStoneModifier: ViewModifier {
    let base: Color
    let cornerRadius: CGFloat
    let crackCount: Int
    let crackWidth: CGFloat
    let bevel: CGFloat
    let seed: UInt64
    
    @State private var cachedCracks: [Path] = []
    @State private var cachedSize: CGSize = .zero
    
    func body(content: Content) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            
            ZStack {
                // Base fill with subtle vertical gradient
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                base.opacity(0.98),
                                base.opacity(0.92),
                                base.opacity(0.96)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Grain + veins (deterministic)
                StoneTexture(seed: seed, cornerRadius: cornerRadius)
                    .clipShape(shape)
                    .blendMode(.multiply)
                    .opacity(0.45)
                
                // Cracks (deterministic & cached)
                ZStack {
                    ForEach(cachedCracks.indices, id: \.self) { i in
                        cachedCracks[i]
                            .stroke(Color.black.opacity(0.55), lineWidth: crackWidth)
                            .blur(radius: 0.2)
                        cachedCracks[i]
                            .stroke(Color.white.opacity(0.22), lineWidth: crackWidth * 0.6)
                            .blendMode(.overlay)
                    }
                }
                .clipShape(shape)
                
                // Bevel + inner shadow for chiseled edge
                shape
                    .stroke(Color.black.opacity(0.25), lineWidth: 1.0)
                    .overlay(
                        shape
                            .inset(by: 0.5)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.35),
                                        Color.black.opacity(0.25)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                            .blur(radius: 0.2)
                    )
                    .overlay(
                        // inner shadow trick
                        shape
                            .fill(Color.black.opacity(0.22))
                            .blur(radius: bevel)
                            .mask(shape)
                            .overlay(shape.stroke(Color.clear))
                            .blendMode(.multiply)
                            .opacity(0.6)
                    )
            }
            .compositingGroup()
            .background(
                // subtle outer drop shadow
                shape.shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            )
            .overlay(content.padding(.all, max(6, bevel * 0.4)))
            .onAppear { ensureCracks(size: size) }
            .onChange(of: size) { _, newValue in ensureCracks(size: newValue) }
        }
    }
    
    private func ensureCracks(size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        if cachedSize != size || cachedCracks.isEmpty {
            cachedCracks = CrackFactory.makeCracks(
                in: CGRect(origin: .zero, size: size),
                count: crackCount,
                seed: seed &+ 0x9E3779B97F4A7C15 // golden ratio mix for variety
            )
            cachedSize = size
        }
    }
}

// MARK: - Stone Texture (deterministic noise + veins)
private struct StoneTexture: View {
    let seed: UInt64
    let cornerRadius: CGFloat
    
    var body: some View {
        Canvas { ctx, size in
            // Grain via grid sampling (stable hash noise)
            let step: CGFloat = 3.0
            for y in stride(from: 0.0, to: size.height, by: step) {
                for x in stride(from: 0.0, to: size.width, by: step) {
                    let v = fbm(x: x, y: y, seed: seed)
                    // Map to subtle darkness + a tiny chance for darker speck
                    let alpha = 0.07 + 0.18 * v
                    let r = 0.7 + 1.4 * v
                    let rect = CGRect(x: x, y: y, width: r, height: r)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.black.opacity(alpha)))
                }
            }
            
            // Veins: long sinuous strokes driven by low-freq noise
            var rng = SplitMix64(seed: seed ^ 0xD1B54A32D192ED03)
            let veinCount = 4
            for i in 0..<veinCount {
                let baseOpacity = 0.16 + 0.05 * Double(i % 2)
                let p = makeVein(size: size, seed: rng.next())
                ctx.stroke(p, with: .color(.black.opacity(baseOpacity)), lineWidth: 0.8)
                ctx.stroke(p, with: .color(.white.opacity(0.12)), lineWidth: 0.4)
            }
        }
        .drawingGroup(opaque: false)
        .allowsHitTesting(false)
    }
    
    // Fractional Brownian Motion (simple value noise)
    private func fbm(x: CGFloat, y: CGFloat, seed: UInt64) -> CGFloat {
        var total: CGFloat = 0
        var amp: CGFloat = 0.6
        var freq: CGFloat = 1/22
        for _ in 0..<4 {
            total += amp * valueNoise(x * freq, y * freq, seed)
            amp *= 0.55
            freq *= 2.15
        }
        return max(0, min(1, total))
    }
    
    private func valueNoise(_ x: CGFloat, _ y: CGFloat, _ seed: UInt64) -> CGFloat {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - CGFloat(xi), yf = y - CGFloat(yi)
        
        let v00 = hash01(xi, yi, seed)
        let v10 = hash01(xi+1, yi, seed)
        let v01 = hash01(xi, yi+1, seed)
        let v11 = hash01(xi+1, yi+1, seed)
        
        let u = smoothstep(xf)
        let v = smoothstep(yf)
        
        let i1 = lerp(v00, v10, u)
        let i2 = lerp(v01, v11, u)
        return lerp(i1, i2, v)
    }
    
    private func makeVein(size: CGSize, seed: UInt64) -> Path {
        var path = Path()
        // start on a random edge
        let edge = Int(truncatingIfNeeded: seed & 3)
        func rnd(_ a: CGFloat, _ b: CGFloat, _ s: inout UInt64) -> CGFloat {
            s = s &* 6364136223846793005 &+ 1
            let u = CGFloat(s % 10_000) / 10_000.0
            return a + (b - a) * u
        }
        var s = seed
        var p: CGPoint
        switch edge {
        case 0: p = CGPoint(x: rnd(0, size.width, &s), y: 0)
        case 1: p = CGPoint(x: size.width, y: rnd(0, size.height, &s))
        case 2: p = CGPoint(x: rnd(0, size.width, &s), y: size.height)
        default: p = CGPoint(x: 0, y: rnd(0, size.height, &s))
        }
        path.move(to: p)
        
        let segments = 22
        for i in 0..<segments {
            // direction influenced by very low-freq noise for a sinuous feel
            let t = CGFloat(i) / CGFloat(segments)
            let nx = valueNoise(p.x * 0.02, p.y * 0.02, seed ^ 0x9E3779B97F4A7C15)
            let ny = valueNoise(p.y * 0.02, p.x * 0.02, seed ^ 0x243F6A8885A308D3)
            let angle = (nx - ny) * .pi * 1.8
            let step: CGFloat = 10 + 18 * (1 - abs(0.5 - t)) // slower in middle
            let q = CGPoint(x: clamp(p.x + cos(angle) * step, 0, size.width),
                            y: clamp(p.y + sin(angle) * step, 0, size.height))
            path.addLine(to: q)
            p = q
        }
        return path
    }
    
    // helpers
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    private func smoothstep(_ x: CGFloat) -> CGFloat { x * x * (3 - 2 * x) }
    private func hash01(_ x: Int, _ y: Int, _ seed: UInt64) -> CGFloat {
        var h = seed
        h ^= UInt64(bitPattern: Int64(x &* 0x27d4eb2d))
        h &+= UInt64(bitPattern: Int64(y &* 0x165667b1))
        h = (h ^ (h >> 33)) &* 0xff51afd7ed558ccd
        h = (h ^ (h >> 33)) &* 0xc4ceb9fe1a85ec53
        h ^= (h >> 33)
        let v = Double(h & 0xFFFFFFFF) / Double(UInt32.max)
        return CGFloat(v)
    }
    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
    private struct SplitMix64 {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}

// MARK: - Crack generation (stable)
private enum CrackFactory {
    static func makeCracks(in rect: CGRect, count: Int, seed: UInt64) -> [Path] {
        var rng = SplitMix64(seed: seed == 0 ? 1 : seed)
        var cracks: [Path] = []
        for _ in 0..<max(0, count) {
            cracks.append(makeOneCrack(in: rect, seed: rng.next()))
        }
        return cracks
    }
    
    private static func makeOneCrack(in rect: CGRect, seed: UInt64) -> Path {
        var s = seed
        func rnd(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
            s = s &* 6364136223846793005 &+ 1
            let u = CGFloat(s % 1_000_000) / 1_000_000.0
            return a + (b - a) * u
        }
        
        // start at a random edge
        let edge = Int(truncatingIfNeeded: seed & 3)
        var p: CGPoint
        switch edge {
        case 0: p = CGPoint(x: rnd(rect.minX, rect.maxX), y: rect.minY)
        case 1: p = CGPoint(x: rect.maxX, y: rnd(rect.minY, rect.maxY))
        case 2: p = CGPoint(x: rnd(rect.minX, rect.maxX), y: rect.maxY)
        default: p = CGPoint(x: rect.minX, y: rnd(rect.minY, rect.maxY))
        }
        
        var path = Path()
        path.move(to: p)
        
        // polyline with occasional sharp turns + micro-branches
        let segments = 14
        for i in 0..<segments {
            let lowNoiseX = valueNoise(p.x * 0.01, p.y * 0.01, seed ^ 0xA5A5A5A5)
            let lowNoiseY = valueNoise(p.y * 0.01, p.x * 0.01, seed ^ 0x5A5A5A5A)
            let angle = (lowNoiseX - lowNoiseY) * .pi * 2.2 + (i % 3 == 0 ? .pi * 0.2 : 0)
            
            let step = rnd(10, 26)
            let q = CGPoint(
                x: clamp(p.x + cos(angle) * step + rnd(-4, 4), rect.minX, rect.maxX),
                y: clamp(p.y + sin(angle) * step + rnd(-4, 4), rect.minY, rect.maxY)
            )
            path.addLine(to: q)
            p = q
            
            // tiny fracture branch
            if (seed >> i) & 1 == 1 && i > 2 {
                var branch = Path()
                branch.move(to: p)
                let ba = angle + rnd(-0.9, 0.9)
                let bl = rnd(8, 18)
                let bp = CGPoint(
                    x: clamp(p.x + cos(ba) * bl, rect.minX, rect.maxX),
                    y: clamp(p.y + sin(ba) * bl, rect.minY, rect.maxY)
                )
                branch.addLine(to: bp)
                path.addPath(branch)
            }
        }
        
        return path
    }
    
    // reuse same helpers as texture
    private static func valueNoise(_ x: CGFloat, _ y: CGFloat, _ seed: UInt64) -> CGFloat {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - CGFloat(xi), yf = y - CGFloat(yi)
        
        func h(_ x: Int, _ y: Int) -> CGFloat {
            var h = seed
            h ^= UInt64(bitPattern: Int64(x &* 0x27d4eb2d))
            h &+= UInt64(bitPattern: Int64(y &* 0x165667b1))
            h = (h ^ (h >> 33)) &* 0xff51afd7ed558ccd
            h = (h ^ (h >> 33)) &* 0xc4ceb9fe1a85ec53
            h ^= (h >> 33)
            let v = Double(h & 0xFFFFFFFF) / Double(UInt32.max)
            return CGFloat(v)
        }
        
        let v00 = h(xi, yi), v10 = h(xi+1, yi), v01 = h(xi, yi+1), v11 = h(xi+1, yi+1)
        let u = smoothstep(xf), v = smoothstep(yf)
        let i1 = v00 + (v10 - v00) * u
        let i2 = v01 + (v11 - v01) * u
        return i1 + (i2 - i1) * v
    }
    private static func smoothstep(_ x: CGFloat) -> CGFloat { x * x * (3 - 2 * x) }
    
    private struct SplitMix64 {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
}

public struct AttentionAttractor: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t: TimeInterval = 0
    @State private var playing = true

    @Binding private var isActive: Bool
    private let cfg: AttentionConfig
    private let duration: UInt64

    public init(isActive: Binding<Bool>, duration: UInt64, config: AttentionConfig) {
        _isActive = isActive
        self.duration = duration
        self.cfg = config
    }

    public func body(content: Content) -> some View {
        content
            // Pure background behind the view – never affects layout.
            .background(
                HaloCanvas(isActive: isActive,
                           period: cfg.period,
                           idlePause: cfg.idlePause,
                           color: cfg.glow,
                           ringWidth: cfg.ringWidth,
                           ringInset: cfg.ringInset,
                           reduceMotion: reduceMotion)
                .allowsHitTesting(false)
            )
            // Tiny badge overlay; fixed size; does not change layout.
            .overlay(badge, alignment: .topTrailing)
            .onChange(of: isActive) { _, on in
                playing = on
                if on {
                    Task {
                        try? await Task.sleep(nanoseconds: duration)
                        await MainActor.run { self.isActive = false }
                    }
                }
            }
    }

    @ViewBuilder
    private var badge: some View {
        if isActive, cfg.showNewBadge {
            Text(cfg.newBadgeText.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(cfg.newBadgeColor)
                        .shadow(color: cfg.newBadgeColor.opacity(0.35), radius: 4, x: 0, y: 1)
                )
                .offset(x: 6, y: -6)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

struct HaloCanvas: View {
    let isActive: Bool
    let period: TimeInterval
    let idlePause: TimeInterval
    let color: Color
    let ringWidth: CGFloat
    let ringInset: CGFloat
    let reduceMotion: Bool

    @State private var time: TimeInterval = Date().timeIntervalSinceReferenceDate

    var body: some View {
        Canvas { ctx, size in
            guard isActive else { return }

            // Circle strictly inside bounds
            let d = min(size.width - 18, size.height - 18)
            let inset = ringInset + ringWidth * 0.5
            let rect = CGRect(
                x: (size.width  - d) / 2 + inset,
                y: (size.height - d) / 2 + inset - 12,
                width:  d - inset * 2,
                height: d - inset * 2
            )
            
            let circle = Path(ellipseIn: rect)
            
            // Time → 0…1 with idle pause
            let total = max(0.001, period + idlePause)
            let phase = time.truncatingRemainder(dividingBy: total)
            let activeFrac = period / total
            let p = phase / total
            let f = (p < activeFrac) ? (p / activeFrac) : 0.0

            // Opacity pulse only (no scale/offset)
            let op = (reduceMotion ? 0.15 : 0.25) * (1 - f)

            let stroke = StrokeStyle(lineWidth: ringWidth, lineCap: .round)
            ctx.stroke(circle, with: .color(color.opacity(op)), style: stroke)
            
            let stroke2 = StrokeStyle(lineWidth: max(1, ringWidth * 0.4), lineCap: .round)
            ctx.stroke(circle, with: .color(color.opacity(op * 0.7)), style: stroke2)
        }
        .backgroundStyle(color.opacity(0.4))
        // Drive time via a hidden TimelineView (no layout/compositing side effects)
        .overlay(
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                Color.clear
                    .onChange(of: ctx.date) { _, date in
                        if isActive { time = date.timeIntervalSinceReferenceDate }
                    }
            }
                .allowsHitTesting(false)
                .opacity(0)   // fully invisible
        )
    }
}

// MARK: - Lock current measured size so overlays never affect layout
private struct LayoutLock: ViewModifier {
    @Binding var size: CGSize
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { size = g.size }
                        .onChange(of: g.size) { _, new in size = new }
                }
            )
    }
}

public enum AttentionStyle {
    case haloBounceSheen        // default: halo + gentle bounce + sheen sweep
    case haloOnly
    case bounceOnly
}

// MARK: - Helpers

private struct GlowOverlay: ViewModifier {
    var glow: Color
    var radius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(color: glow, radius: radius)
            .shadow(color: glow.opacity(0.5), radius: radius * 0.5)
            .shadow(color: glow.opacity(0.25), radius: radius * 0.25)
    }
}

/// Drives `t` using a TimelineView without blocking the main thread.
private struct TimelineDriver: ViewModifier {
    @Binding var playing: Bool
    let tick: (TimeInterval) -> Void
    
    func body(content: Content) -> some View {
        ZStack {
            content
            if playing {
                TimelineView(.animation(minimumInterval: 1/60.0)) { ctx in
                    Color.clear
                        .onChange(of: ctx.date) { _, date in
                            tick(date.timeIntervalSinceReferenceDate)
                        }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

public struct AttentionConfig {
    public let tint: Color
    public let glow: Color
    public let ringWidth: CGFloat
    public let ringInset: CGFloat
    public let period: TimeInterval
    public let idlePause: TimeInterval
    public let showNewBadge: Bool
    public let newBadgeText: String
    public let newBadgeColor: Color
    
    init(tint: Color = .white, glow: Color = .cyan.opacity(0.45), ringWidth: CGFloat = 3, ringInset: CGFloat = 2, period: TimeInterval = 1.8, idlePause: TimeInterval = 1.2, showNewBadge: Bool = true, newBadgeText: String = "NEW", newBadgeColor: Color = .pink) {
        self.tint = tint
        self.glow = glow
        self.ringWidth = ringWidth
        self.ringInset = ringInset
        self.period = period
        self.idlePause = idlePause
        self.showNewBadge = showNewBadge
        self.newBadgeText = newBadgeText
        self.newBadgeColor = newBadgeColor
    }
}

extension View {
    func circleReveal(trigger: Binding<Bool>) -> some View { modifier(CenterPinnedBurstModifier(trigger: trigger)) }
    func realisticCell(color: Color) -> some View { modifier(RealisticCellModifier(color: color)) }
    func elevated(cornerRadius: CGFloat) -> some View { modifier(ElevatedModifier(cornerRadius: cornerRadius)) }
    func loading(show: Bool) -> some View { modifier(LoadingViewModifier(show: show)) }
    func brickBorder(color: Color = .gray, lineWidth: CGFloat = 6, brickLength: CGFloat = 24, gapLength: CGFloat = 8, cornerRadius: CGFloat = 8) -> some View { modifier(BrickBorderModifier(color: color, lineWidth: lineWidth, brickLength: brickLength, gapLength: gapLength, cornerRadius: cornerRadius)) }
    func realStone(base: Color = Color(white: 0.78), cornerRadius: CGFloat = 4, crackCount: Int = 3, crackWidth: CGFloat = 1.2, bevel: CGFloat = 8, seed: UInt64 = 1337) -> some View { modifier(RealStoneModifier(base: base, cornerRadius: cornerRadius, crackCount: crackCount, crackWidth: crackWidth, bevel: bevel, seed: seed)) }
    func attentionIfNew(isActive: Binding<Bool>, duration: UInt64 = 8_000_000_000, config: AttentionConfig = AttentionConfig()) -> some View { modifier(AttentionAttractor(isActive: isActive, duration: duration, config: config)) }
}
