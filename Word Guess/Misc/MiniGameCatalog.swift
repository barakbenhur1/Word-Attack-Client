//
//  MiniGameCatalog.swift
//  WordZap
//
//  Created by Barak Ben Hur on 14/09/2025.
//

import SwiftUI
import Foundation
import CoreMotion

// MARK: - Types exposed to the Hub

public enum MiniResult { case found(Character), foundMany([Character]), nothing, close }

public enum MiniKind: CaseIterable, Hashable {
    case sand, wax, fog, sonar, ripple,
         magnet, frost, tag, aiMerchant, symbolPick,
         symbolPuzzle, luckyWait, claw, memory, cardShuffle,
         popBalloon, sliderAlign, longPress, shakeReveal, tapTarget
    
    public var title: String {
        switch self {
        case .sand: "Sand Dig".localized
        case .wax: "Wax Press".localized
        case .fog: "Fog Wipe".localized
        case .sonar: "Sonar".localized
        case .ripple: "Ripples".localized
        case .magnet: "Magnet".localized
        case .frost: "Frost".localized
        case .tag: "Playing Tag".localized
        case .aiMerchant: "AI Merchant".localized
        case .symbolPick: "Spot the Letter".localized
        case .symbolPuzzle: "Symbol Puzzle".localized
        case .luckyWait: "Lucky Wait".localized
        case .claw: "Claw".localized
        case .memory: "Memory".localized
        case .cardShuffle: "Card Shuffle".localized
        case .popBalloon: "Pop Balloon".localized
        case .sliderAlign: "Align".localized
        case .longPress: "Hold to Reveal".localized
        case .shakeReveal: "Shake to Reveal".localized
        case .tapTarget: "Tap Target".localized
        }
    }
    
    public var icon: String {
        switch self {
        case .sand: "hand.draw"
        case .wax: "hand.point.up.left"
        case .fog: "wind"
        case .sonar: "dot.radiowaves.left.and.right"
        case .ripple: "aqi.low"
        case .magnet: "paperclip.circle.fill"
        case .frost: "snowflake"
        case .tag: "figure.run.circle.fill"
        case .aiMerchant: "brain.head.profile"
        case .symbolPick: "textformat.abc.dottedunderline"
        case .symbolPuzzle: "puzzlepiece.extension"
        case .luckyWait: "hourglass"
        case .claw: "hand.tap"
        case .memory: "rectangle.grid.2x2"
        case .cardShuffle: "suit.heart.fill"
        case .popBalloon: "balloon.2.fill"
        case .sliderAlign: "slider.horizontal.3"
        case .longPress: "hand.tap.fill"
        case .shakeReveal: "iphone.gen3.radiowaves.left.and.right"
        case .tapTarget: "scope"
        }
    }
    
    // Base probability that a slot *contains a letter* (games can still end in failure).
    public var baseLetterChance: Double {
        switch self {
        case .fog:    return 0.22
        case .sand:   return 0.45
        case .wax:    return 0.45
        case .sonar:  return 0.66
        case .ripple: return 0.35
        case .magnet: return 0.40
        case .frost:  return 0.30
        case .tag:   return 1.0
        case .aiMerchant: return 1.0
        case .symbolPick: return 1.0
        case .symbolPuzzle: return 1.0
        case .luckyWait: return 0.0
        case .claw:        return 0.80
        case .memory:      return 1.00
        case .cardShuffle: return 0.90
        case .popBalloon:  return 1.00 // letter is present; user has 3 tries
        case .sliderAlign: return 1.00
        case .longPress:   return 1.00
        case .shakeReveal: return 1.00
        case .tapTarget:   return 0.80
        }
    }
    
    // Appearance weights (relative).
    public static func weights(hasAI: Bool) -> [(MiniKind, Double)] {
        var w: [(MiniKind, Double)] = [
            (.sand, 11), (.wax, 11), (.fog, 11), (.sonar, 11), (.ripple, 11),
            (.magnet, 10), (.frost, 9), (.tag, 8),
            // keep existing 4
            (.symbolPick, 5), (.symbolPuzzle, 5), (.luckyWait, 5),
            // new 8
            (.claw, 7), (.memory, 7), (.cardShuffle, 7), (.popBalloon, 7),
            (.sliderAlign, 6), (.longPress, 6), (.shakeReveal, 6), (.tapTarget, 6)
        ]
        if hasAI { w.append((.aiMerchant, 3)) }
        return w
    }
    
    // TTL heuristic (seconds)
    public func ttl() -> Int {
        switch self {
        case .aiMerchant: return 20
        case .symbolPick: return 15
        case .symbolPuzzle: return 30
        case .luckyWait: return 12
        case .tag: return max(12, Int(12 * 2.2))
        case .fog: return max(12, Int(6 * 2.2))
        case .sand, .wax: return max(12, Int(14 * 2.2))
        case .sonar: return max(12, Int(20 * 2.2))
        default: return max(12, Int(12 * 2.2))
        }
    }
}

// Slot used by the hub
public struct MiniSlot: Identifiable, Hashable {
    public let id = UUID()
    public let kind: MiniKind
    public let expiresAt: Date
    public let containsLetter: Bool
    public let seededLetter: Character?
    public var secondsLeft: Int { max(0, Int(expiresAt.timeIntervalSinceNow.rounded())) }
}

// MARK: - Provider

public final class MiniGameCatalog {
    public init() {}
    
    // Build initial 8 with per-kind cap (<=2).
    // Build initial 8 with hard uniqueness (no duplicates).
    public func uniqueInitialSlots(hasAI: Bool,
                                   hub: PremiumHubModel) -> [MiniSlot] {
        // Per requirement: at startup / reset all → 8 distinct kinds.
        // We intentionally force the cap to 1 here (ignore the incoming default),
        // so the initial board is always unique.
        let initialCapPerKind = 1
        
        var slots: [MiniSlot] = []
        var counts: [MiniKind:Int] = [:]
        
        while slots.count < 8 {
            let k = nextKind(hasAI: hasAI, counts: counts, capPerKind: initialCapPerKind)
            let s = makeSlot(kind: k, hub: hub)
            slots.append(s)
            counts[k, default: 0] += 1
        }
        return slots
    }
    
    // Replacement respecting per-kind cap (<=2)
    public func makeSlot(hasAI: Bool,
                         hub: PremiumHubModel,
                         existing: [MiniSlot],
                         capPerKind: Int = 2) -> MiniSlot {
        var counts = countsByKind(existing)
        let k = nextKind(hasAI: hasAI, counts: counts, capPerKind: capPerKind)
        counts[k, default: 0] += 1
        return makeSlot(kind: k, hub: hub)
    }
    
    // Factory for UI — returns the correct SwiftUI view for this slot.
    public func view(for slot: MiniSlot,
                     hub: PremiumHubModel,
                     onDone: @escaping (MiniResult) -> Void) -> AnyView {
        let hasLetter = slot.containsLetter || CGFloat.random(in: 0...1) <= CGFloat.random(in: 0...0.7)
        switch slot.kind {
        case .sand:         return AnyView(SandDigMini(hasLetter: hasLetter, letter: slot.seededLetter, onDone: onDone))
        case .wax:          return AnyView(WaxPressMini(hasLetter: hasLetter, letter: slot.seededLetter, onDone: onDone))
        case .fog:          return AnyView(FogWipeMini(hasLetter: hasLetter, letter: slot.seededLetter, onDone: onDone))
        case .sonar:        return AnyView(SonarMini(hasLetter: hasLetter, seed: slot.seededLetter, onDone: onDone))
        case .ripple:       return AnyView(RippleMini(hasLetter: hasLetter, letter: slot.seededLetter, onDone: onDone))
        case .magnet:       return AnyView(MagnetMini(hasLetter: hasLetter, letter: slot.seededLetter, onDone: onDone))
        case .frost:        return AnyView(FrostMini(hasLetter: hasLetter, letter: slot.seededLetter, onDone: onDone))
        case .tag:          return AnyView(PlayTagMini(hasLetter: hasLetter, seed: slot.seededLetter, onDone: onDone))
        case .aiMerchant:   return AnyView(AIMerchantMini(deadline: slot.expiresAt, ai: hub.aiDifficulty, hub: hub, onDone: onDone))
        case .symbolPick:   return AnyView(SymbolPickMini(deadline: slot.expiresAt, hub: hub, hasLetter: slot.containsLetter, onDone: onDone))
        case .symbolPuzzle: return AnyView(SymbolPuzzleMini(deadline: slot.expiresAt, hub: hub, onDone: onDone))
        case .luckyWait:    return AnyView(LuckyWaitMini(deadline: slot.expiresAt, hub: hub, onDone: onDone))
        case .claw:         return AnyView(ClawMini(deadline: slot.expiresAt, hub: hub, letter: slot.seededLetter, onDone: onDone))
        case .memory:       return AnyView(MemoryMini(deadline: slot.expiresAt, hub: hub, letter: slot.seededLetter, onDone: onDone))
        case .cardShuffle:  return AnyView(CardShuffleMini(deadline: slot.expiresAt, hub: hub, letter: slot.seededLetter, onDone: onDone))
        case .popBalloon:   return AnyView(PopBalloonMini(deadline: slot.expiresAt, hub: hub, letter: slot.seededLetter, onDone: onDone))
        case .sliderAlign:  return AnyView(SliderAlignMini(deadline: slot.expiresAt, hub: hub, letter: slot.seededLetter, onDone: onDone))
        case .longPress:    return AnyView(LongPressMini(deadline: slot.expiresAt, hub: hub, letter: slot.seededLetter, onDone: onDone))
        case .shakeReveal:  return AnyView(ShakeRevealMini(deadline: slot.expiresAt, hub: hub, letter: slot.seededLetter, onDone: onDone))
        case .tapTarget:    return AnyView(TapTargetMini(deadline: slot.expiresAt, hub: hub, letter: slot.seededLetter, onDone: onDone))
        }
    }
    
    // MARK: - Internals
    
    private func countsByKind(_ slots: [MiniSlot]) -> [MiniKind:Int] {
        var m: [MiniKind:Int] = [:]
        for s in slots { m[s.kind, default: 0] += 1 }
        return m
    }
    
    private func nextKind(hasAI: Bool,
                          counts: [MiniKind:Int],
                          capPerKind: Int) -> MiniKind {
        let pool = MiniKind.weights(hasAI: hasAI)
            .filter { counts[$0.0, default: 0] < capPerKind }
        let total = pool.reduce(0.0) { $0 + $1.1 }
        let r = Double.random(in: 0..<max(total, 0.0001))
        var acc = 0.0
        for (k, w) in pool {
            acc += w
            if r < acc { return k }
        }
        return pool.last?.0 ?? .sand
    }
    
    private func makeSlot(kind: MiniKind, hub: PremiumHubModel) -> MiniSlot {
        let contains = Double.random(in: 0...1) < kind.baseLetterChance
        let seed: Character? = contains ? hub.pickLetterForOffer() : nil
        
        // Special cases that *always* contain seed (by game design):
        let guaranteedKinds: Set<MiniKind> = [.aiMerchant, .symbolPick, .symbolPuzzle,
                                              .memory, .cardShuffle, .popBalloon,
                                              .sliderAlign, .longPress, .shakeReveal]
        let finalContains = guaranteedKinds.contains(kind) ? true : contains
        let finalSeed = finalContains ? (seed ?? hub.pickLetterForOffer()) : nil
        
        return MiniSlot(kind: kind,
                        expiresAt: Date().addingTimeInterval(TimeInterval(kind.ttl())),
                        containsLetter: finalContains,
                        seededLetter: finalSeed)
    }
}

// MARK: - MINI GAMES

private struct SandDigMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void
    
    @State private var strokes: [CGPoint] = []
    @State private var hit = false
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"
    
    @State private var showingLetter = false
    @State private var overlayScale: CGFloat = 0.92
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(PremiumPalette.sand)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack)
                        .position(letterPos)
                        .mask(RevealMask(points: strokes))
                        .animation(.easeInOut(duration: 0.2), value: strokes.count)
                }
                Canvas { ctx, _ in
                    for p in strokes {
                        let rect = CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)
                        ctx.fill(Ellipse().path(in: rect), with: .color(Color.dynamicWhite.opacity(0.08)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                
                if showingLetter {
                    Text(String(seeded))
                        .font(.system(size: 84, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack)
                        .scaleEffect(overlayScale)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    strokes.append(g.location)
                    if hasLetter && !hit {
                        let d = hypot(g.location.x - letterPos.x, g.location.y - letterPos.y)
                        if d < 40 { hit = true }
                    }
                }
                .onEnded { _ in
                    let success = hasLetter && hit
                    if success {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showingLetter = true
                            overlayScale = 1.06
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            onDone(.found(seeded))
                        }
                    } else {
                        onDone(.nothing)
                    }
                })
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 60
                letterPos = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                    y: .random(in: inset...(geo.size.height - inset)))
            }
        }
        .frame(height: 300)
    }
}

private struct RevealMask: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for pt in points { p.addEllipse(in: CGRect(x: pt.x-28, y: pt.y-28, width: 56, height: 56)) }
        return p
    }
}

struct WaxPressMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void
    
    @State private var pressPoint: CGPoint?
    @State private var clarity: CGFloat = 0
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"
    
    @State private var showingLetter = false
    @State private var overlayScale: CGFloat = 0.92
    
    // finger feedback
    @State private var ringPulse = false
    
    // tuning
    private let inset: CGFloat = 70          // keep letter comfortably away from edges
    private let clarityGain: CGFloat = 0.02  // how fast wax clears while pressing
    
    private func revealRadius(for clarity: CGFloat) -> CGFloat {
        40 + 40 * clarity
    }

    private func clampedPoint(in rect: CGRect, inset: CGFloat) -> (CGPoint) -> CGPoint {
        { p in
            CGPoint(
                x: min(max(p.x, rect.minX + inset), rect.maxX - inset),
                y: min(max(p.y, rect.minY + inset), rect.maxY - inset)
            )
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let shape  = RoundedRectangle(cornerRadius: 18, style: .continuous)
            let bounds = CGRect(origin: .zero, size: geo.size)
            let clamp  = clampedPoint(in: bounds, inset: inset)
            
            ZStack {
                // Base wax
                shape
                    .fill(PremiumPalette.wax)
                    .overlay(
                        // sheen that clears as you press
                        LinearGradient(
                            colors: [
                                Color.dynamicWhite.opacity(0.7),
                                Color.dynamicWhite.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(shape)
                        .opacity(0.7 - 0.6 * clarity)
                    )
                    .overlay(shape.stroke(PremiumPalette.stroke, lineWidth: 1))
                
                // Letter (revealed by the press mask)
                if hasLetter {
                    Text(String(seeded))
                        .font(
                            .system(
                                size: min(geo.size.width, geo.size.height) * 0.42,
                                weight: .heavy,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(Color.dynamicBlack.opacity(0.9))
                        .position(letterPos)
                        .mask(
                            Group {
                                if let p = pressPoint {
                                    // Center the reveal exactly at the finger point
                                    let r = revealRadius(for: clarity)
                                    Circle()
                                        .frame(width: r * 2, height: r * 2)
                                        .position(p)
                                }
                            }
                        )
                        .animation(.easeInOut(duration: 0.15), value: clarity)
                }
                
                // Finger-move visual feedback (clipped)
                if let p = pressPoint {
                    let r = revealRadius(for: clarity)
                    
                    // soft glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.dynamicBlack.opacity(0.28 * (0.4 + clarity * 0.6)),
                                    Color.dynamicBlack.opacity(0.02)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: r * 2.5
                            )
                        )
                        .frame(width: r * 2.5, height: r * 2.5)
                        .position(p)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                    
                    // ring pulse (same center as reveal)
                    Circle()
                        .stroke(Color.dynamicBlack.opacity(0.45), lineWidth: 2)
                        .frame(width: r * 2, height: r * 2)
                        .position(p)
                        .scaleEffect(ringPulse ? 1.06 : 0.96)
                        .opacity(0.9)
                        .shadow(color: Color.dynamicBlack.opacity(0.22), radius: 3, y: 1)
                        .animation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true), value: ringPulse)
                        .onAppear { ringPulse = true }
                        .onDisappear { ringPulse = false }
                        .allowsHitTesting(false)
                }
                
                if showingLetter {
                    Text(String(seeded))
                        .font(.system(size: 84, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack)
                        .scaleEffect(overlayScale)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // clip everything to the rounded rect & use it as hit area
            .clipShape(shape)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        // only react if finger is inside the shape
                        let inside = shape.path(in: bounds).contains(g.location)
                        if inside {
                            // keep press point fully inside the safe area to avoid edge artifacts
                            pressPoint = clamp(g.location)
                            clarity = min(1, clarity + clarityGain)
                        } else {
                            // if outside, hide feedback but keep current clarity (no increase)
                            pressPoint = nil
                        }
                    }
                    .onEnded { _ in
                        let success: Bool
                        if hasLetter, let p = pressPoint {
                            let r = revealRadius(for: clarity)
                            success = hypot(p.x - letterPos.x, p.y - letterPos.y) <= r
                        } else { success = false }
                        
                        if success {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showingLetter = true
                                overlayScale = 1.06
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDone(.found(seeded)) }
                        } else {
                            onDone(.nothing)
                        }
                        
                        // reset visuals
                        pressPoint = nil
                        clarity = 0
                    }
            )
            .onAppear {
                // seed letter and position
                seeded = letter ?? PremiumHubModel.randomLetter()
                letterPos = CGPoint(
                    x: .random(in: inset...(geo.size.width  - inset)),
                    y: .random(in: inset...(geo.size.height - inset))
                )
            }
            .onChange(of: geo.size) { _, newSize in
                // keep letter in-bounds on size changes (rotation, iPad split, etc.)
                let newBounds = CGRect(origin: .zero, size: newSize)
                letterPos = clampedPoint(in: newBounds, inset: inset)(letterPos)
            }
        }
        .frame(height: 300)
    }
}

private struct FogWipeMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void

    @State private var strokes: [CGPoint] = []
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"
    @State private var finished = false
    
    @State private var showingLetter = false
    @State private var overlayScale: CGFloat = 0.92

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Revealed area = dynamicWhite (white in light mode)
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.dynamicWhite.opacity(0.98))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(PremiumPalette.stroke, lineWidth: 1)
                    )

                if hasLetter {
                    Text(String(seeded))
                        .font(.system(
                            size: min(geo.size.width, geo.size.height) * 0.42,
                            weight: .heavy,
                            design: .rounded
                        ))
                        .foregroundStyle(Color.dynamicBlack)     // <-- letter is dynamicBlack
                        .position(letterPos)
                        .mask(RevealMask(points: strokes))   // only shows where wiped
                }

                // ---- Gray fog that gets cleared to expose white underneath ----
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.dynamicBlack.opacity(0.18))   // <-- gray fog
                    .mask(
                        // Mask shows fog everywhere (white) EXCEPT where strokes are (black)
                        ZStack {
                            Rectangle().fill(.white) // fully visible fog
                            Canvas { ctx, _ in
                                ctx.addFilter(.alphaThreshold(min: 0.01))
                                ctx.addFilter(.blur(radius: 6))
                                for p in strokes {
                                    let rect = CGRect(x: p.x - 24, y: p.y - 24, width: 48, height: 48)
                                    // draw BLACK to CUT HOLES from the fog
                                    ctx.fill(Ellipse().path(in: rect), with: .color(.dynamicWhite))
                                }
                            }
                        }
                        .compositingGroup()
                        .luminanceToAlpha()
                    )
                
                if showingLetter {
                    Text(String(seeded))
                        .font(.system(size: 84, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack)
                        .scaleEffect(overlayScale)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard !finished else { return }
                        strokes.append(g.location)
                    }
                    .onEnded { _ in
                        guard !finished else { return }
                        finished = true
                        let success = hasLetter && strokes.contains { hypot($0.x - letterPos.x, $0.y - letterPos.y) < 40 }
                        if success {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showingLetter = true
                                overlayScale = 1.06
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDone(.found(seeded)) }
                        } else {
                            onDone(.nothing)
                        }
                    }
                
            )
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                letterPos = CGPoint(
                    x: .random(in: inset...(geo.size.width - inset)),
                    y: .random(in: inset...(geo.size.height - inset))
                )
            }
        }
        .frame(height: 260)
    }
}

private struct SonarMini: View {
    let hasLetter: Bool
    let seed: Character?                // stable seed from slot
    let onDone: (MiniResult) -> Void
    
    @State private var target: CGPoint = .zero
    @State private var pings: [Ping] = []
    @State private var solved = false
    @State private var letterToShow: Character? = nil   // ← frozen once
    
    // success animation state
    @State private var letterScale: CGFloat = 1.0
    @State private var successAt: Date? = nil
    
    struct Ping: Identifiable { let id = UUID(); let center: CGPoint; let date: Date; let strength: Double }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.dynamicWhite.opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                
                GridPattern().stroke(Color.dynamicBlack.opacity(0.15), lineWidth: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                
                // sonar pings
                TimelineView(.animation) { timeline in
                    Canvas { ctx, _ in
                        for ping in pings {
                            let t = timeline.date.timeIntervalSince(ping.date)
                            let r = CGFloat(20 + t * 180)
                            let alpha = max(0, 1.0 - t / 1.6)
                            let rect = CGRect(x: ping.center.x - r/2, y: ping.center.y - r/2, width: r, height: r)
                            let color = PremiumPalette.sonar.opacity(alpha * (0.4 + 0.6 * ping.strength))
                            ctx.stroke(Circle().path(in: rect), with: .color(color), lineWidth: 2)
                        }
                    }
                }
                
                // letter (only after success), animated in-place
                if solved, let ch = letterToShow {
                    Text(String(ch))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.40,
                                      weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack)
                        .position(target)
                        .scaleEffect(letterScale)
                        .shadow(color: Color.dynamicBlack.opacity(0.6), radius: 6, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // success ripples centered on the target
                if let t0 = successAt {
                    TimelineView(.animation) { tl in
                        Canvas { ctx, _ in
                            let dt = tl.date.timeIntervalSince(t0)
                            guard dt <= 0.6 else { return }
                            for i in 0..<3 {
                                let t = dt - Double(i) * 0.06
                                guard t >= 0 else { continue }
                                let p = t / 0.6
                                let r = CGFloat(12 + p * 130)
                                let a = 1.0 - p
                                let rect = CGRect(x: target.x - r, y: target.y - r, width: r*2, height: r*2)
                                ctx.stroke(Circle().path(in: rect),
                                           with: .color(Color.dynamicBlack.opacity(0.35 * a)),
                                           lineWidth: 2)
                            }
                        }
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { g in
                    let p = g.location
                    let d = max(1, hypot(p.x - target.x, p.y - target.y))
                    let norm = max(0, 1 - Double(min(d, 220) / 220))
                    pings.append(Ping(center: p, date: Date(), strength: norm))
                    
                    if d < 36 {
                        // success → animate letter at target (bounce + ripples), then close
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        letterScale = 0.98
                        withAnimation(.spring(response: 0.50, dampingFraction: 0.75)) { solved = true }
                        successAt = Date()
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) { letterScale = 1.12 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) { letterScale = 1.00 }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                            if let ch = letterToShow { onDone(.found(ch)) } else { onDone(.nothing) }
                        }
                    }
                }
            )
            .onAppear {
                letterToShow = hasLetter ? seed : nil  // freeze once
                let inset: CGFloat = 70
                target = CGPoint(
                    x: .random(in: inset...(geo.size.width - inset)),
                    y: .random(in: inset...(geo.size.height - inset))
                )
            }
        }
        .frame(height: 300)
    }
}

private struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for x in stride(from: rect.minX, through: rect.maxX, by: 24) {
            p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for y in stride(from: rect.minY, through: rect.maxY, by: 24) {
            p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}

private struct RippleMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void

    struct Ring: Identifiable { let id = UUID(); let center: CGPoint; let start: Date }

    @State private var rings: [Ring] = []
    @State private var target: CGPoint = .zero
    @State private var seeded: Character = "A"
    @State private var solved = false
    @State private var frameTimer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()

    // success animation (letter)
    @State private var letterScale: CGFloat = 1.0
    @State private var successAt: Date? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.dynamicWhite.opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))

                // Letter appears only when solved, and animates in place
                if solved, hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.40,
                                      weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack)
                        .position(target)
                        .scaleEffect(letterScale)
                        .shadow(color: Color.dynamicBlack.opacity(0.6), radius: 6, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }

                // Continuous user-generated ripples
                TimelineView(.animation) { tl in
                    Canvas { ctx, _ in
                        for ring in rings {
                            let t = tl.date.timeIntervalSince(ring.start)
                            let r = CGFloat(10 + t * 150)
                            let alpha = max(0, 1.0 - t / 1.4)
                            let rect = CGRect(x: ring.center.x - r/2, y: ring.center.y - r/2, width: r, height: r)
                            ctx.stroke(Circle().path(in: rect), with: .color(.teal.opacity(alpha)), lineWidth: 2)
                        }
                    }
                }

                // Success burst ripples centered on the target
                if let t0 = successAt {
                    TimelineView(.animation) { tl in
                        Canvas { ctx, _ in
                            let dt = tl.date.timeIntervalSince(t0)
                            guard dt <= 0.6 else { return }
                            for i in 0..<3 {
                                let t = dt - Double(i) * 0.06
                                guard t >= 0 else { continue }
                                let p = t / 0.6
                                let r = CGFloat(12 + p * 130)
                                let a = 1.0 - p
                                let rect = CGRect(x: target.x - r, y: target.y - r, width: r*2, height: r*2)
                                ctx.stroke(Circle().path(in: rect),
                                           with: .color(Color.dynamicBlack.opacity(0.35 * a)),
                                           lineWidth: 2)
                            }
                        }
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onTapGesture { p in
                rings.append(Ring(center: p, start: Date()))
            }
            .onReceive(frameTimer) { now in
                // clean old rings
                rings.removeAll { now.timeIntervalSince($0.start) > 1.6 }

                guard hasLetter, !solved else { return }

                // detect a ring passing over the target
                for ring in rings {
                    let t = now.timeIntervalSince(ring.start)
                    let r = CGFloat(10 + t * 150)
                    if abs(r - hypot(ring.center.x - target.x, ring.center.y - target.y)) < 14 {
                        // success → animate letter in place
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        solved = true
                        successAt = now
                        letterScale = 0.98
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) { letterScale = 1.12 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) { letterScale = 1.00 }
                        }
                        // close after brief feedback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onDone(.found(seeded)) }
                        break
                    }
                }
            }
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                target = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                 y: .random(in: inset...(geo.size.height - inset)))
            }
        }
        .frame(height: 280)
    }
}

private struct MagnetMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void
    
    struct Particle: Identifiable { let id = UUID(); var p: CGPoint; var v: CGVector }
    
    @State private var filings: [Particle] = []
    @State private var magnetPos: CGPoint = .zero
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"
    
    @State private var closeTicks = 0
    @State private var physicsTimer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    
    // Reveal state
    @State private var discovered = false
    @State private var captureAt: Date? = nil
    @State private var letterScale: CGFloat = 0.92
    @State private var letterOpacity: Double = 0.04   // faint by default
    
    var body: some View {
        GeometryReader { geo in
            let bounds = geo.size
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.dynamicWhite.opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                
                // Rails (purely decorative)
                Canvas { ctx, _ in
                    var path = Path()
                    for _ in 0..<7 {
                        let w = Double.random(in: 60...90)
                        let h = Double.random(in: 10...16)
                        let x = Double.random(in: 20...(bounds.width-80))
                        let y = Double.random(in: 20...(bounds.height-20))
                        path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h),
                                            cornerSize: CGSize(width: 7, height: 7))
                    }
                    ctx.stroke(path, with: .color(Color.dynamicBlack.opacity(0.08)), lineWidth: 5)
                }
                
                // Letter (faint → bright when discovered), animates in place
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(bounds.width, bounds.height) * 0.42,
                                      weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack.opacity(letterOpacity))
                        .scaleEffect(letterScale)
                        .position(letterPos)
                        .shadow(color: Color.dynamicBlack.opacity(discovered ? 0.6 : 0.0),
                                radius: discovered ? 6 : 0, y: discovered ? 2 : 0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: letterScale)
                        .animation(.easeInOut(duration: 0.18), value: letterOpacity)
                }
                
                // Metal filings
                Canvas { ctx, _ in
                    for f in filings {
                        let rect = CGRect(x: f.p.x - 2, y: f.p.y - 2, width: 4, height: 4)
                        ctx.fill(Ellipse().path(in: rect), with: .color(Color.dynamicBlack.opacity(0.8)))
                    }
                }
                
                // Magnet (user)
                Image(systemName: "paperclip.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(PremiumPalette.accent)
                    .position(magnetPos)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in guard !discovered else { return }; magnetPos = g.location }
                        .onEnded { _ in
                            guard !discovered else { return }
                            let d = hypot(magnetPos.x - letterPos.x, magnetPos.y - letterPos.y)
                            if hasLetter && d < 46 { triggerReveal() }
                            else { onDone(.nothing) }
                        })
                
                // Ripple burst when revealed (centered on the letter)
                TimelineView(.animation) { tl in
                    if let start = captureAt {
                        let dt = tl.date.timeIntervalSince(start)
                        Canvas { ctx, _ in
                            let c = letterPos
                            for i in 0..<3 {
                                let t = dt - Double(i) * 0.06
                                guard t >= 0, t <= 0.6 else { continue }
                                let p = t / 0.6
                                let r = CGFloat(12 + p * 130)
                                let a = 1.0 - p
                                let rect = CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2)
                                ctx.stroke(Circle().path(in: rect),
                                           with: .color(Color.dynamicBlack.opacity(0.35 * a)),
                                           lineWidth: 2)
                            }
                        }
                    }
                }
            }
            .onReceive(physicsTimer) { _ in
                guard !discovered else { return }
                
                // Update filings with magnet pull
                var updated: [Particle] = []
                for var f in filings {
                    let dx = magnetPos.x - f.p.x, dy = magnetPos.y - f.p.y
                    let d = max(16, hypot(dx, dy))
                    let pull: CGFloat = 1400 / (d*d)
                    f.v.dx += dx / d * pull
                    f.v.dy += dy / d * pull
                    f.v.dx *= 0.92; f.v.dy *= 0.92
                    f.p.x += f.v.dx; f.p.y += f.v.dy
                    updated.append(f)
                }
                filings = updated
                
                // Proximity dwell → reveal
                if hasLetter {
                    let d = hypot(magnetPos.x - letterPos.x, magnetPos.y - letterPos.y)
                    closeTicks = d < 48 ? (closeTicks + 1) : 0
                    if closeTicks > 15 { triggerReveal() }  // ~0.25s at 60fps
                }
            }
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                letterPos = CGPoint(x: .random(in: inset...(bounds.width - inset)),
                                    y: .random(in: inset...(bounds.height - inset)))
                magnetPos = CGPoint(x: bounds.width/2, y: 28)
                filings = (0..<90).map { _ in
                    Particle(p: CGPoint(x: .random(in: 20...(bounds.width-20)),
                                        y: .random(in: 20...(bounds.height-20))),
                             v: CGVector(dx: 0, dy: 0))
                }
            }
        }
        .frame(height: 300)
    }
    
    // MARK: - Reveal & close after animation
    private func triggerReveal() {
        guard !discovered else { return }
        discovered = true
        captureAt = Date()
        
        // pop + brighten letter (in place)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            letterScale = 1.10
            letterOpacity = 1.0
        }
        // settle a bit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                letterScale = 1.00
            }
        }
        // close after users see it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
            onDone(.found(seeded))
        }
    }
}

private struct FrostMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void
    
    @State private var heatPoints: [CGPoint] = []
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"
    
    // finger feedback
    @State private var touchPoint: CGPoint?
    @State private var heatLevel: CGFloat = 0
    @State private var ringPulse = false
    
    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            let bounds = CGRect(origin: .zero, size: geo.size)
            
            ZStack {
                // background + stroke
                shape
                    .fill(Color.dynamicWhite.opacity(0.88))
                    .overlay(shape.stroke(PremiumPalette.stroke, lineWidth: 1))
                
                // letter reveal
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.42,
                                      weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack)
                        .position(letterPos)
                        .mask(HeatMask(points: heatPoints))
                }
                
                // frost texture
                FrostOverlay()
                    .opacity(0.9)
                
                // ===== Finger-move visual feedback (clipped by shape) =====
                if let p = touchPoint {
                    // warm glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.dynamicBlack.opacity(0.28 * (0.4 + heatLevel * 0.6)),
                                    Color.dynamicBlack.opacity(0.02)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 40 + 120 * heatLevel
                            )
                        )
                        .frame(width: 80 + 220 * heatLevel, height: 80 + 220 * heatLevel)
                        .position(p)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                    
                    // breathing ring
                    Circle()
                        .stroke(Color.dynamicWhite.opacity(0.45), lineWidth: 2)
                        .frame(width: 38 + 40 * heatLevel, height: 38 + 40 * heatLevel)
                        .position(p)
                        .scaleEffect(ringPulse ? 1.06 : 0.96)
                        .opacity(0.9)
                        .shadow(color: .white.opacity(0.22), radius: 3, y: 1)
                        .animation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true),
                                   value: ringPulse)
                        .onAppear { ringPulse = true }
                        .onDisappear { ringPulse = false }
                        .allowsHitTesting(false)
                }
            }
            // ensure NOTHING renders outside the rounded rect
            .clipShape(shape)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let inside = shape.path(in: bounds).contains(g.location)
                        if inside {
                            touchPoint = g.location
                            heatPoints.append(g.location)
                            heatLevel = min(1, heatLevel + 0.04)
                        } else {
                            // outside → hide the indicators and do not add heat
                            touchPoint = nil
                        }
                    }
                    .onEnded { _ in
                        let success = hasLetter &&
                        heatPoints.contains { hypot($0.x - letterPos.x, $0.y - letterPos.y) < 42 }
                        onDone(success ? .found(seeded) : .nothing)
                        touchPoint = nil
                        heatLevel = 0
                    }
            )
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                letterPos = CGPoint(
                    x: .random(in: inset...(geo.size.width - inset)),
                    y: .random(in: inset...(geo.size.height - inset))
                )
            }
        }
        .frame(height: 280)
    }
}

private struct HeatMask: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for pt in points { p.addEllipse(in: CGRect(x: pt.x-28, y: pt.y-28, width: 56, height: 56)) }
        return p
    }
}

private struct FrostOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            for _ in 0..<200 {
                let r = CGFloat.random(in: 1...2.6)
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                ctx.fill(Ellipse().path(in: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(Color.dynamicBlack.opacity(0.6)))
            }
        }.blur(radius: 1.2)
    }
}

private struct PlayTagMini: View {
    // API parity; this mini always contains a letter
    let hasLetter: Bool
    let seed: Character?
    let onDone: (MiniResult) -> Void
    
    // Letter (no default “A” flash)
    @State private var letterText: String = ""
    private var isHE: Bool { Locale.current.identifier.lowercased().hasPrefix("he") }
    private var letterFont: Font {
        .system(size: 42, weight: .heavy, design: isHE ? .default : .rounded)
    }
    
    // Entities
    @State private var ball = CGPoint(x: 40, y: 40)
    @State private var target = CGPoint(x: 260, y: 220)
    @State private var velTarget = CGVector(dx: 1.6, dy: -1.2)
    
    // UX & capture
    @State private var solved = false
    @State private var captureAt: Date? = nil
    @State private var letterScale: CGFloat = 1.0
    @State private var letterOpacity: Double = 1.0
    @State private var ballScale: CGFloat = 1.0
    
    // Idle & smoothing (to drive target AI)
    @State private var lastBallPos = CGPoint(x: 40, y: 40)
    @State private var lastMoveAt = Date()
    @State private var accLP = CGVector(dx: 0, dy: 0)
    
    // Wander
    @State private var wander = CGVector(dx: 0, dy: 0)
    @State private var wanderTarget = CGVector(dx: 0, dy: 0)
    @State private var lastWanderUpdate = Date()
    
    // Edge dwell → escape / center cruise
    @State private var lastTickAt = Date()
    @State private var edgeDwell: Double = 0
    @State private var escapeUntil: Date? = nil
    @State private var centerCruiseUntil: Date? = nil
    @State private var lastCenterCruise = Date(timeIntervalSince1970: 0)
    
    // Timing
    @State private var ticker = Timer.publish(every: 1/140, on: .main, in: .common).autoconnect()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    // Drag gate — only move when drag begins on the ball
    @State private var isDragging = false
    @State private var dragStartBall = CGPoint.zero   // <- ball position when drag began
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.dynamicWhite.opacity(0.88))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                
                // Letter (script-aware). Hidden until seeded → avoids “A” flash.
                if !letterText.isEmpty {
                    Text(letterText)
                        .font(letterFont)
                        .foregroundStyle(Color.dynamicBlack)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(PremiumPalette.accent.opacity(0.25)))
                        .scaleEffect(letterScale)
                        .opacity(letterOpacity)
                        .position(target)
                        .accessibilityLabel(Text(letterText))
                } else {
                    Circle().fill(Color.dynamicBlack.opacity(0.20))
                        .frame(width: 12, height: 12)
                        .position(target)
                }
                
                // Player ball — drag must START on the ball (contentShape: Circle)
                Circle()
                    .fill(Color.dynamicBlack)
                    .frame(width: 22, height: 22)
                    .shadow(radius: 2, y: 1)
                    .scaleEffect(ballScale)
                    .position(ball)
                    .contentShape(Circle()) // hit-test only the circle
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                guard !solved else { return }
                                
                                // First onChanged of this gesture: capture where the ball started.
                                if !isDragging {
                                    isDragging = true
                                    dragStartBall = ball
                                }
                                
                                // Move by translation from the captured start (prevents “jump”).
                                let p = CGPoint(
                                    x: dragStartBall.x + g.translation.width,
                                    y: dragStartBall.y + g.translation.height
                                )
                                ball = clamp(point: p, in: geo.size)
                                lastMoveAt = Date()
                                lastBallPos = ball
                                checkCatch(in: geo.size) // live capture while dragging
                            }
                            .onEnded { _ in
                                isDragging = false
                                checkCatch(in: geo.size)
                            }
                    )
                
                RoundedRectangle(cornerRadius: 18).stroke(Color.dynamicBlack.opacity(0.1), lineWidth: 8)
                
                // capture ripple
                TimelineView(.animation) { tl in
                    if let start = captureAt {
                        let dt = tl.date.timeIntervalSince(start)
                        Canvas { ctx, _ in
                            let c = target
                            for i in 0..<3 {
                                let t = dt - Double(i) * 0.06
                                guard t >= 0 else { continue }
                                let dur: Double = reduceMotion ? 0.25 : 0.6
                                guard t <= dur else { continue }
                                let p = t / dur
                                let r = CGFloat(10 + p * 120)
                                let a = 1.0 - p
                                let rect = CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2)
                                ctx.stroke(Circle().path(in: rect),
                                           with: .color(Color.dynamicBlack.opacity(0.35 * a)),
                                           lineWidth: 2)
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle()) // does not affect ball-only drag
            .onReceive(ticker) { _ in tick(geo.size) }
            .onAppear {
                // Seed letter (always present)
                let ch = seed ?? PremiumHubModel.randomLetter()
                letterText = String(ch)
                
                // Safe spawns
                let inset: CGFloat = 36
                ball = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                               y: .random(in: inset...(geo.size.height - inset)))
                target = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                 y: .random(in: inset...(geo.size.height - inset)))
                lastBallPos = ball
                lastMoveAt = Date()
                lastTickAt = Date()
            }
        }
        .frame(height: 280)
    }
    
    // MARK: - Per-frame AI for target (unchanged)
    private func tick(_ size: CGSize) {
        guard !solved else { return }
        
        let now = Date()
        let dt = max(0.0, now.timeIntervalSince(lastTickAt))
        lastTickAt = now
        
        // idle detection
        let moveDist = hypot(ball.x - lastBallPos.x, ball.y - lastBallPos.y)
        if moveDist > 0.4 { lastMoveAt = now }
        lastBallPos = ball
        let isIdle = now.timeIntervalSince(lastMoveAt) > 0.45
        
        // wander update
        let wanderPeriod = isIdle ? 1.2 : 0.7
        if now.timeIntervalSince(lastWanderUpdate) > wanderPeriod {
            let a = Double.random(in: 0..<(2 * .pi))
            let m = Double.random(in: (isIdle ? 0.05...0.22 : 0.20...0.55))
            wanderTarget = CGVector(dx: CGFloat(cos(a) * m), dy: CGFloat(sin(a) * m))
            lastWanderUpdate = now
        }
        let wanderEase: CGFloat = isIdle ? 0.03 : 0.05
        wander.dx += (wanderTarget.dx - wander.dx) * wanderEase
        wander.dy += (wanderTarget.dy - wander.dy) * wanderEase
        
        // geometry
        var p = target
        var acc = CGVector(dx: 0, dy: 0)
        
        let inset: CGFloat = 36
        let minX = inset, maxX = size.width - inset
        let minY = inset, maxY = size.height - inset
        let center = CGPoint(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5)
        
        let toBall = CGVector(dx: ball.x - p.x, dy: ball.y - p.y)
        let dist = max(0.001, hypot(toBall.dx, toBall.dy))
        let dirToBall = CGVector(dx: toBall.dx / dist, dy: toBall.dy / dist)
        let toCenter = CGVector(dx: center.x - p.x, dy: center.y - p.y)
        let lenC = max(0.001, hypot(toCenter.dx, toCenter.dy))
        let dirToCenter = CGVector(dx: toCenter.dx/lenC, dy: toCenter.dy/lenC)
        let perpToBall = CGVector(dx: -dirToBall.dy, dy: dirToBall.dx)
        let tangentSign: CGFloat = (perpToBall.dx * dirToCenter.dx + perpToBall.dy * dirToCenter.dy) >= 0 ? 1 : -1
        
        // walls / edges
        let wallRange: CGFloat = 70
        let dxL = p.x - minX, dxR = maxX - p.x
        let dyT = p.y - minY, dyB = maxY - p.y
        let nearEdgeDist = min(min(dxL, dxR), min(dyT, dyB))
        let nearEdge = nearEdgeDist < 34
        
        // edge dwell → escape
        if nearEdge { edgeDwell += dt } else { edgeDwell = max(0, edgeDwell - dt * 1.5) }
        if edgeDwell > 0.85, escapeUntil == nil {
            escapeUntil = now.addingTimeInterval(0.7)
            edgeDwell = 0.25
        }
        
        // periodic short center cruises
        if nearEdge && now.timeIntervalSince(lastCenterCruise) > 2.6 {
            centerCruiseUntil = now.addingTimeInterval(0.5)
            lastCenterCruise = now
        }
        let inEscape = (escapeUntil.map { now < $0 } ?? false)
        let inCruise  = (centerCruiseUntil.map { now < $0 } ?? false)
        
        // 1) Flee player
        let safeRadius: CGFloat  = 180
        let panicRadius: CGFloat = 80
        let tClose = max(0, min(1, (safeRadius - dist) / (safeRadius - panicRadius)))
        let fleeBase: CGFloat  = isIdle ? 0.15 : 0.50
        let fleeScale: CGFloat = isIdle ? 1.20 : 2.00
        let fleeMag = (inEscape || inCruise) ? (fleeBase * 0.65) : (fleeBase + fleeScale * tClose)
        acc.dx += -dirToBall.dx * fleeMag
        acc.dy += -dirToBall.dy * fleeMag
        
        // 2) Side-step around player
        let slipMag = (isIdle ? 0.10 : 0.25) + (isIdle ? 0.30 : 0.80) * tClose
        let curveBoost: CGFloat = inCruise ? 0.35 : 0
        acc.dx += perpToBall.dx * (tangentSign * (slipMag + curveBoost))
        acc.dy += perpToBall.dy * (tangentSign * (slipMag + curveBoost))
        
        // 3) Wall & corner repulsion
        func push(_ d: CGFloat, scale: CGFloat) -> CGFloat {
            guard d < wallRange else { return 0 }
            let x = max(0, (wallRange - d) / wallRange)
            return scale * x * x
        }
        let wallScale: CGFloat = (isIdle || inEscape || inCruise) ? 1.0 : 2.1
        acc.dx += push(dxL, scale: wallScale) - push(dxR, scale: wallScale)
        acc.dy += push(dyT, scale: wallScale) - push(dyB, scale: wallScale)
        
        // corner escape
        let cornerRange: CGFloat = 44
        if min(dxL, dxR) < cornerRange && min(dyT, dyB) < cornerRange {
            let nx: CGFloat = (dxL < dxR) ? 1 : -1
            let ny: CGFloat = (dyT < dyB) ? 1 : -1
            let norm = 1 / max(0.001, hypot(nx, ny))
            let boost: CGFloat = (isIdle || inEscape || inCruise) ? 1.4 : 2.2
            acc.dx += nx * norm * boost
            acc.dy += ny * norm * boost
        }
        
        // 4) Escape/cruise pulls
        if inEscape || inCruise {
            acc.dx += dirToCenter.dx * (inEscape ? 0.70 : 0.55)
            acc.dy += dirToCenter.dy * (inEscape ? 0.70 : 0.55)
            let perpC = CGVector(dx: -dirToCenter.dy, dy: dirToCenter.dx)
            acc.dx += perpC.dx * 0.25 * (tangentSign)
            acc.dy += perpC.dy * 0.25 * (tangentSign)
        } else if isIdle {
            acc.dx += dirToCenter.dx * 0.25
            acc.dy += dirToCenter.dy * 0.25
        } else {
            let perpC = CGVector(dx: -dirToCenter.dy, dy: dirToCenter.dx)
            acc.dx += perpC.dx * 0.10 * tangentSign
            acc.dy += perpC.dy * 0.10 * tangentSign
        }
        
        // 5) Wander
        acc.dx += wander.dx
        acc.dy += wander.dy
        
        // smoothing
        accLP.dx = accLP.dx * 0.90 + acc.dx * 0.10
        accLP.dy = accLP.dy * 0.90 + acc.dy * 0.10
        
        let desiredDX = velTarget.dx + accLP.dx
        let desiredDY = velTarget.dy + accLP.dy
        
        velTarget.dx += (desiredDX - velTarget.dx) * 0.12
        velTarget.dy += (desiredDY - velTarget.dy) * 0.12
        
        // never steer toward the ball
        let towardDot = velTarget.dx * dirToBall.dx + velTarget.dy * dirToBall.dy
        if towardDot > 0 {
            velTarget.dx -= dirToBall.dx * towardDot * 1.05
            velTarget.dy -= dirToBall.dy * towardDot * 1.05
        }
        
        // idle damping
        if isIdle {
            velTarget.dx *= 0.97
            velTarget.dy *= 0.97
            let dz: CGFloat = 0.08
            if abs(velTarget.dx) < dz { velTarget.dx = 0 }
            if abs(velTarget.dy) < dz { velTarget.dy = 0 }
        }
        
        // clamp
        velTarget.dx = clampMag(velTarget.dx, maxValue: 2.6)
        velTarget.dy = clampMag(velTarget.dy, maxValue: 2.6)
        
        // integrate + soft bounce
        p.x += velTarget.dx
        p.y += velTarget.dy
        
        let hitLeft  = p.x < minX
        let hitRight = p.x > maxX
        let hitTop   = p.y < minY
        let hitBot   = p.y > maxY
        
        if hitLeft  { p.x = minX; velTarget.dx *= -0.95 }
        if hitRight { p.x = maxX; velTarget.dx *= -0.95 }
        if hitTop   { p.y = minY; velTarget.dy *= -0.95 }
        if hitBot   { p.y = maxY; velTarget.dy *= -0.95 }
        
        if hitLeft  { p.x += 0.8 }
        if hitRight { p.x -= 0.8 }
        if hitTop   { p.y += 0.8 }
        if hitBot   { p.y -= 0.8 }
        
        target = p
        checkCatch(in: size)
    }
    
    // MARK: - Helpers
    
    private func clamp(point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: max(20, min(size.width - 20, point.x)),
                y: max(20, min(size.height - 20, point.y)))
    }
    private func clampMag(_ v: CGFloat, maxValue: CGFloat) -> CGFloat {
        min(maxValue, max(-maxValue, v))
    }
    
    private func checkCatch(in size: CGSize, threshold: CGFloat = 18) {
        guard !solved else { return }
        if hypot(ball.x - target.x, ball.y - target.y) <= threshold {
            solved = true
            captureAt = Date()
            
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            
            let snapDur = reduceMotion ? 0.15 : 0.28
            let popDur  = reduceMotion ? 0.15 : 0.28
            
            withAnimation(.spring(response: snapDur, dampingFraction: 0.75)) {
                ball = target
                ballScale = 1.15
            }
            withAnimation(.spring(response: popDur, dampingFraction: 0.7)) {
                letterScale = 1.18
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.10 : 0.18)) {
                withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) {
                    letterScale = 0.82
                    letterOpacity = 0.0
                    ballScale = 1.0
                }
            }
            
            let resolveDelay = reduceMotion ? 0.35 : 0.6
            DispatchQueue.main.asyncAfter(deadline: .now() + resolveDelay) {
                let ch = letterText.isEmpty ? PremiumHubModel.randomLetter() : Character(letterText)
                onDone(.found(ch))
            }
        }
    }
}

// MARK: - NEW: AI Merchant (now uses hub to offer undiscovered letters and window preference)

private struct AIMerchantMini: View {
    let deadline: Date
    let ai: AIDifficulty?
    let hub: PremiumHubModel
    var onDone: (MiniResult) -> Void
    
    @State private var offered: [Character] = []
    @State private var picked: Set<Character> = []
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let ai {
                    Image(ai.image)
                        .resizable()
                        .scaledToFit()
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.dynamicBlack.opacity(0.12)))
                        .overlay(Circle().stroke(Color.dynamicBlack.opacity(0.6), lineWidth: 1))
                        .foregroundColor(Color.dynamicBlack)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ai.name).font(.subheadline.weight(.semibold))
                        Text("take this").font(.caption).foregroundStyle(Color.dynamicBlack.opacity(0.7))
                    }
                } else { Text("Unavailable").font(.subheadline) }
                Spacer()
//                // CountdownPill(deadline: deadline)
            }
            .padding(.bottom, 6)
            
            // Spaced AI tokens (adaptive grid)
            WrapLetters(letters: offered, picked: picked, spacing: 6, runSpacing: 8) { ch in
                guard !picked.contains(ch) else { return }
                picked.insert(ch)
                onDone(.found(ch))
                if picked.count == offered.count { onDone(.close) }
            }
        }
        .onAppear {
            let count = ai?.premiumLetterCount ?? 0
            offered = hub.pickLettersForOffer(count: count).shuffled()
        }
    }
}

private struct ThickGlassCell: View {
    let character: Character
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.dynamicBlack.opacity(0.04))
            Text(String(character))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.dynamicBlack)
                .scaleEffect(1.06)
                .opacity(0.85)
                .blur(radius: 1.2)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thickMaterial)
                .overlay(
                    LinearGradient(
                        colors: [Color.dynamicBlack.opacity(0.45), Color.dynamicBlack.opacity(0.10), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .blendMode(.screen)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.dynamicBlack.opacity(0.16), lineWidth: 1)
                )
                .overlay(GlassSpeckle().opacity(0.05)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                .shadow(color: .black.opacity(0.30), radius: 7, y: 3)
                .allowsHitTesting(false)
        }
        .frame(height: 56)
    }
}

fileprivate struct GlassSpeckle: View {
    var body: some View {
        Canvas { ctx, size in
            for _ in 0..<36 {
                let r = CGFloat.random(in: 0.6...1.6)
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                ctx.fill(
                    Ellipse().path(in: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(Color.dynamicBlack.opacity(0.8))
                )
            }
        }
        .blur(radius: 0.8)
    }
}

fileprivate struct WrapLetters: View {
    let letters: [Character]
    let picked: Set<Character>
    var spacing: CGFloat = 14
    var runSpacing: CGFloat = 12
    let tap: (Character) -> Void
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: spacing)],
                  spacing: runSpacing) {
            ForEach(letters, id: \.self) { ch in
                Button { tap(ch) } label: {
                    Text(String(ch))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Color.dynamicBlack)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(PremiumPalette.accent))
                        .overlay(Circle().stroke(Color.dynamicBlack.opacity(0.5), lineWidth: 1))
                        .opacity(picked.contains(ch) ? 0.25 : 1)
                        .scaleEffect(picked.contains(ch) ? 0.82 : 1)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8),
                                   value: picked.contains(ch))
                }
                .disabled(picked.contains(ch))
            }
        }
                  .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Symbol Pick (blurred grid) — respects `hasLetter`
private struct SymbolPickMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    let hasLetter: Bool                    // ← NEW
    var onDone: (MiniResult) -> Void
    
    @State private var grid: [(Character, Bool)] = []   // (char, isLetter)
    @State private var attemptsLeft: Int = 3
    @State private var tried: Set<Int> = []             // wrong picks
    @State private var fired: Set<Int> = []             // pressed this finger already
    @State private var revealed: Set<Int> = []          // for pop/reveal
    @State private var successIndex: Int? = nil         // winning cell index
    
    // success animation state (cell-local visuals are keyed by successIndex)
    @State private var winPulse = false
    @State private var successAt: Date? = nil
    
    private let animDuration: Double = 0.30
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(hasLetter ? "Tap a letter" : "Tap tiles") // ← no false promise
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(i < attemptsLeft ? Color.dynamicBlack.opacity(0.9)
                                                       : Color.dynamicBlack.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text("\(attemptsLeft)/3")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.dynamicBlack.opacity(0.8))
                        .padding(.vertical, 3).padding(.horizontal, 6)
                        .background(Capsule().fill(Color.dynamicBlack.opacity(0.12)))
                }
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(0..<grid.count, id: \.self) { i in
                    let (ch, isL)   = grid[i]
                    let isWrong     = tried.contains(i)
                    let isRevealed  = revealed.contains(i)
                    let isWin       = (successIndex == i)
                    
                    ZStack {
                        // base glass tile
                        ThickGlassCell(character: ch)
                            .opacity(isWrong ? 0.95 : 1.0)
                            .overlay(
                                Group {
                                    if isWin {
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.dynamicBlack, lineWidth: 3)
                                            .shadow(color: Color.dynamicBlack.opacity(0.6), radius: 6, y: 2)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                            )
                        
                        // reveal glyph when turned
                        if isRevealed && !isWrong {
                            Text(String(ch))
                                .font(.system(.title, design: .rounded).weight(.heavy))
                                .foregroundStyle(Color.dynamicBlack)
                                .scaleEffect(isWin ? (winPulse ? 1.18 : 1.08) : 1.02)
                                .shadow(color: Color.dynamicBlack.opacity(isWin ? 0.6 : 0.3),
                                        radius: isWin ? 6 : 3, y: isWin ? 2 : 1)
                                .transition(.scale.combined(with: .opacity))
                                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRevealed)
                                .animation(.spring(response: 0.30, dampingFraction: 0.75), value: winPulse)
                        }
                        
                        // wrong mark
                        if isWrong {
                            Image(systemName: "slash.circle")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(Color.dynamicBlack.opacity(0.85))
                                .transition(.opacity)
                        }
                        
                        // success ripples centered on the cell
                        if isWin, let t0 = successAt {
                            TimelineView(.animation) { tl in
                                Canvas { ctx, size in
                                    let dt = tl.date.timeIntervalSince(t0)
                                    guard dt <= 0.6 else { return }
                                    let center = CGPoint(x: size.width/2, y: size.height/2)
                                    for i in 0..<3 {
                                        let t = dt - Double(i) * 0.06
                                        guard t >= 0 else { continue }
                                        let p = t / 0.6
                                        let r = CGFloat(10 + p * 120)
                                        let a = 1.0 - p
                                        let rect = CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)
                                        ctx.stroke(Circle().path(in: rect),
                                                   with: .color(Color.dynamicBlack.opacity(0.35 * a)),
                                                   lineWidth: 2)
                                    }
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .scaleEffect(isWin ? (winPulse ? 1.10 : 1.06) : (isRevealed ? 1.05 : 1.0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRevealed)
                    .animation(.spring(response: 0.30, dampingFraction: 0.75), value: winPulse)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !fired.contains(i),
                                      successIndex == nil,
                                      !isWrong,
                                      attemptsLeft > 0 else { return }
                                fired.insert(i)
                                select(i: i, isLetter: isL, ch: ch)
                            }
                    )
                    .allowsHitTesting(!isWrong && successIndex == nil && attemptsLeft > 0)
                }
            }
        }
        .onAppear {
            fired.removeAll()
            var items: [(Character, Bool)] = []
            if hasLetter {
                // mix of letters + decoys, ensure at least one letter
                items = (0..<16).map { _ in
                    Bool.random()
                    ? (hub.pickLetterForOffer(), true)
                    : (PremiumHubModel.randomNonLetter(), false)
                }
                if !items.contains(where: { $0.1 }) {
                    let idx = Int.random(in: 0..<16)
                    items[idx] = (hub.pickLetterForOffer(), true)
                }
            } else {
                // decoys only — guarantees no letter present
                items = (0..<16).map { _ in (PremiumHubModel.randomNonLetter(), false) }
            }
            grid = items.shuffled()
        }
    }
    
    @MainActor
    private func select(i: Int, isLetter: Bool, ch: Character) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            _ = revealed.insert(i)
        }
        attemptsLeft -= 1
        
        // success only if the board is supposed to have a letter AND this cell is a letter
        if hasLetter && isLetter {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            successIndex = i
            successAt = Date()
            winPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.8)) { winPulse = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                onDone(.found(ch))
            }
        } else {
            tried.insert(i)
            if attemptsLeft == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + animDuration) {
                    onDone(.nothing)
                }
            }
        }
    }
}

// MARK: - NEW: Symbol Puzzle (rotate & decide) – uses hub for letter
private struct SymbolPuzzleMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    var onDone: (MiniResult) -> Void

    @State private var symbol: Character = "?"
    @State private var isLetter = false
    @State private var angle: Double = [0, 90, 180, 270].randomElement()!

    // success feedback on the letter (no fullscreen overlay)
    @State private var solved = false
    @State private var pulse = false
    @State private var successAt: Date? = nil

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Is this a letter?").font(.subheadline.weight(.semibold))
                Spacer()
                // CountdownPill(deadline: deadline)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.dynamicBlack.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.dynamicBlack.opacity(0.12)))

                // Letter in the puzzle
                Text(String(symbol))
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.dynamicBlack)
                    .rotationEffect(.degrees(angle))
                    .scaleEffect(pulse ? 1.12 : 1.0) // quick bounce
                    .shadow(color: Color.dynamicBlack.opacity(solved ? 0.6 : 0), radius: solved ? 6 : 0, y: solved ? 2 : 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: angle)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: pulse)
                    .padding(10)

                // subtle success ring ripples, centered on the letter
                if let t0 = successAt {
                    TimelineView(.animation) { tl in
                        Canvas { ctx, size in
                            let dt = tl.date.timeIntervalSince(t0)
                            // 0.6s lifetime
                            guard dt <= 0.6 else { return }
                            let center = CGPoint(x: size.width/2, y: size.height/2)
                            for i in 0..<3 {
                                let t = dt - Double(i) * 0.06
                                guard t >= 0 else { continue }
                                let p = t / 0.6
                                let r = CGFloat(12 + p * 120)
                                let a = 1.0 - p
                                let rect = CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)
                                ctx.stroke(Circle().path(in: rect),
                                           with: .color(Color.dynamicBlack.opacity(0.35 * a)),
                                           lineWidth: 2)
                            }
                        }
                    }
                }
            }
            .frame(height: 200)

            HStack(spacing: 12) {
                Button { angle -= 90 } label: {
                    Label("Rotate", systemImage: "rotate.left")
                }
                .buttonStyle(.borderedProminent)

                Button { angle += 90 } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                .buttonStyle(.bordered)

                Spacer()

                // YES → success only if it's a letter and currently upright
                Button {
                    let upright = Int(((angle.truncatingRemainder(dividingBy: 360)) + 360)
                                        .truncatingRemainder(dividingBy: 360))
                    let symmetrical = symbol.lowercased() == "o" || symbol.lowercased() == "x" || symbol.lowercased() == "z"
                    let success = isLetter && (upright % 360 == 0 || (symmetrical && (upright % 180 == 0)))
                    if success {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        // snap to perfect upright (in case of -0/+360 drift), bounce, and show ripples
                        let snapTo: Double = (upright % 360 == 0) ? 0 : 180
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { angle = snapTo }
                        pulse = true
                        successAt = Date()
                        solved = true
                        // release pulse back to 1.0 shortly
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { pulse = false }
                        }
                        // close after brief feedback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            onDone(.found(symbol))
                        }
                    } else {
                        onDone(.nothing)
                    }
                } label: { Text("Yes").bold() }
                .buttonStyle(.borderedProminent)

                // NO → always nothing, no reveal animation
                Button { onDone(.nothing) } label: { Text("No") }
                    .buttonStyle(.bordered)
            }
        }
        .onAppear {
            if Bool.random() {
                symbol = hub.pickLetterForOffer()
                isLetter = true
            } else {
                symbol = PremiumHubModel.randomNonLetter()
                isLetter = false
            }
        }
    }
}

// MARK: - NEW: Lucky Wait – uses hub for letter

private struct LuckyWaitMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    var onDone: (MiniResult) -> Void
    
    @State private var started = Date()
    @State private var resolved = false
    @State private var showLetter: Character? = nil
    @State private var showNo = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Wait 5 seconds…").font(.subheadline.weight(.semibold))
                Spacer()
                // CountdownPill(deadline: deadline)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.dynamicBlack.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.dynamicBlack.opacity(0.1)))
                    .frame(height: 140)
                if let ch = showLetter {
                    Text(String(ch))
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack)
                        .transition(.scale.combined(with: .opacity))
                } else if showNo {
                    Text("Letter not found")
                        .font(.headline)
                        .foregroundStyle(Color.dynamicBlack.opacity(0.8))
                        .transition(.opacity)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.dynamicBlack)
                }
            }
        }
        .onAppear { started = Date() }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { now in
            guard !resolved else { return }
            if now.timeIntervalSince(started) >= 5 {
                resolved = true
                if Bool.random() {
                    let ch = hub.pickLetterForOffer()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showLetter = ch
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        onDone(.found(ch))
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.35)) { showNo = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        onDone(.nothing)
                    }
                }
            }
        }
    }
}

// MARK: - Claw (auto side-to-side, tap to drop, 3 tries, reveal before close)

struct ClawMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    let letter: Character?
    var onDone: (MiniResult) -> Void
    
    @State private var seed: Character = "A"
    
    @State private var clawX: CGFloat = 0.5   // 0..1
    @State private var clawDir: CGFloat = 1.0 // +right / -left
    @State private var dropY: CGFloat = 0.0   // 0..1 progress
    @State private var moving = true
    @State private var dropping = false
    @State private var triesLeft = 3
    
    @State private var targetX: CGFloat = .random(in: 0.18...0.82)
    @State private var showLetterOverlay = false
    @State private var overlayScale: CGFloat = 0.9
    
    private let tick = Timer.publish(every: 1/180, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Tries: \(triesLeft)/3").font(.caption).foregroundStyle(Color.dynamicBlack.opacity(0.75))
                Spacer()
                // CountdownPill(deadline: deadline)
            }
            
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18).fill(Color.dynamicWhite.opacity(0.88))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.dynamicWhite.opacity(0.12)))
                // rail
                Rectangle().fill(Color.dynamicBlack.opacity(0.34))
                    .frame(height: 4).offset(y: 8)
                
                // claw
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.dynamicBlack)
                    .offset(x: (clawX - 0.5) * 260,
                            y: 18 + dropY * 150)
                    .animation(.linear(duration: 0.001), value: clawX)
                    .animation(.easeInOut(duration: 0.3), value: dropY)
                
                // prize (shows where the letter is)
                Text(String(seed))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.dynamicBlack.opacity(0.75))
                    .offset(x: (targetX - 0.5) * 260, y: 160)
                
                // success overlay (big letter)
                if showLetterOverlay {
                    Text(String(seed))
                        .font(.system(size: 84, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack)
                        .scaleEffect(overlayScale)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
            .onTapGesture(perform: drop)
            .onReceive(tick) { _ in
                guard moving, !dropping else { return }
                clawX += clawDir * 0.006  // speed
                if clawX < 0.08 { clawX = 0.08; clawDir = 1 }
                if clawX > 0.92 { clawX = 0.92; clawDir = -1 }
            }
        }
        .onAppear { seed = letter ?? hub.pickLetterForOffer() }
    }
    
    private func drop() {
        guard !dropping, triesLeft > 0 else { return }
        dropping = true; moving = false
        withAnimation(.easeInOut(duration: 0.35)) { dropY = 1.0 }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            let success = abs(clawX - targetX) < 0.12
            if success {
                revealAndClose()
            } else {
                triesLeft -= 1
                withAnimation(.easeInOut(duration: 0.28)) { dropY = 0.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dropping = false
                    moving = triesLeft > 0
                    if triesLeft == 0 { onDone(.nothing) }
                }
            }
        }
    }
    
    private func revealAndClose() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showLetterOverlay = true
            overlayScale = 1.05
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onDone(.found(seed))
        }
    }
}

// MARK: - Memory (preview start, then hide, remember; reveal before close)

struct MemoryMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    let letter: Character?
    var onDone: (MiniResult) -> Void
    
    struct Card: Identifiable { let id = UUID(); let content: String; var isFaceUp = false; var isMatched = false }
    
    @State private var seed: Character = "A"
    @State private var cards: [Card] = []
    @State private var indicesChosen: [Int] = []
    @State private var strikes = 0
    @State private var previewing = true
    @State private var showingLetter = false
    @State private var overlayScale: CGFloat = 0.95
    
    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                HStack {
                    Text(previewing ? "Memorize…" : "Find the pair").font(.caption)
                    Spacer()
                    // CountdownPill(deadline: deadline)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(cards.indices, id: \.self) { i in
                        let c = cards[i]
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(Color.dynamicBlack.opacity(c.isFaceUp || c.isMatched ? 0.12 : 0.06))
                            RoundedRectangle(cornerRadius: 12).stroke(Color.dynamicBlack.opacity(0.15))
                            if c.isFaceUp || c.isMatched {
                                Text(c.content)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.dynamicBlack)
                            }
                        }
                        .frame(height: 56)
                        .onTapGesture { if !previewing { flip(i) } }
                        .opacity(c.isMatched ? 0.35 : 1)
                        .animation(.easeInOut(duration: 0.18), value: cards[i].isFaceUp)
                    }
                }
                
                Text("Strikes: \(strikes)/3")
                    .font(.caption).foregroundStyle(Color.dynamicBlack.opacity(0.7))
            }
            
            if showingLetter {
                Text(String(seed))
                    .font(.system(size: 84, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.dynamicBlack)
                    .scaleEffect(overlayScale)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear { setup() }
    }
    
    private func setup() {
        seed = letter ?? hub.pickLetterForOffer()
        var pool: [String] = [String(seed), String(seed)]
        let symbols = Array("!@#$%^&*?+-=<>").map(String.init).shuffled()
        for i in 0..<5 { pool.append(contentsOf: [symbols[i], symbols[i]]) }
        cards = pool.shuffled().map { Card(content: $0, isFaceUp: true) }
        
        // preview then hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            previewing = false
            for i in cards.indices { cards[i].isFaceUp = false }
        }
    }
    
    private func flip(_ i: Int) {
        guard !cards[i].isMatched, !cards[i].isFaceUp else { return }
        cards[i].isFaceUp = true
        indicesChosen.append(i)
        
        if indicesChosen.count == 2 {
            let a = indicesChosen[0], b = indicesChosen[1]
            indicesChosen.removeAll()
            let match = cards[a].content == cards[b].content
            if match {
                cards[a].isMatched = true
                cards[b].isMatched = true
                if cards[a].content == String(seed) {
                    revealAndClose()
                }
            } else {
                strikes += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    cards[a].isFaceUp = false
                    cards[b].isFaceUp = false
                    if strikes >= 3 { onDone(.nothing) }
                }
            }
        }
    }
    
    private func revealAndClose() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showingLetter = true
            overlayScale = 1.05
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onDone(.found(seed))
        }
    }
}

// MARK: - Card Shuffle (visible shuffle you can follow; 1 chance)

struct CardShuffleMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    let letter: Character?
    var onDone: (MiniResult) -> Void
    
    private enum Phase { case reveal, shuffling, awaitPick, resolving }
    private struct Card: Identifiable { let id = UUID(); let isLetter: Bool }
    
    @State private var phase: Phase = .reveal
    @State private var seed: Character = "A"
    
    // three cards (one is the letter)
    @State private var cards: [Card] = []
    // slot index (0,1,2) for each card id → drives visible positions
    @State private var slotFor: [UUID:Int] = [:]
    
    // tap/selection state
    @State private var pickedSlot: Int? = nil
    @State private var canPick: Bool = false
    @State private var selectedID: UUID? = nil
    @State private var selectedScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let cardSize = CGSize(width: 86, height: 118)
                let spacing: CGFloat = 18
                let total = cardSize.width * 3 + spacing * 2
                let startX = (geo.size.width - total) / 2 + cardSize.width / 2
                let y = geo.size.height / 2
                
                ZStack {
                    // cards
                    ForEach(cards) { card in
                        let slot = slotFor[card.id] ?? 0
                        SingleCardView(
                            face: displayFace(for: card),
                            highlighted: (phase == .reveal && card.isLetter) ||
                            (phase == .resolving && selectedID == card.id && card.isLetter)
                        )
                        .frame(width: cardSize.width, height: cardSize.height)
                        .position(x: startX + CGFloat(slot) * (cardSize.width + spacing), y: y)
                        .zIndex(card.id == selectedID ? 10 : Double(3 - slot))
                        .scaleEffect(card.id == selectedID ? selectedScale : 1.0)
                        .overlay(
                            Group {
                                if card.id == selectedID {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(.white, lineWidth: 3)
                                        .shadow(color: .white.opacity(0.6), radius: 6, y: 2)
                                }
                            }
                        )
                        .animation(.easeInOut(duration: 0.26), value: slotFor)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedScale)
                    }
                }
                .contentShape(Rectangle())
                .overlay(
                    // tap layers aligned to slots (only when awaiting pick)
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { slot in
                            Color.clear
                                .frame(width: cardSize.width, height: cardSize.height)
                                .contentShape(Rectangle())
                                .onTapGesture { pick(slot: slot) }
                                .allowsHitTesting(canPick && pickedSlot == nil)
                        }
                    }
                        .frame(width: total, height: cardSize.height)
                        .position(x: geo.size.width/2, y: y)
                )
            }
            .frame(height: 150)
        }
        .onAppear { setupAndRun() }
    }
    
    // MARK: - Faces
    
    private func displayFace(for card: Card) -> String {
        switch phase {
        case .reveal:
            return card.isLetter ? String(seed) : "×"
        case .shuffling, .awaitPick:
            return "?"
        case .resolving:
            // Only reveal the chosen card; others stay facedown
            if card.id == selectedID {
                return card.isLetter ? String(seed) : "×"
            } else {
                return "?"
            }
        }
    }
    
    // MARK: - Flow
    
    private func setupAndRun() {
        seed = letter ?? hub.pickLetterForOffer()
        
        // make three cards (1 letter + 2 decoys)
        let cs = [Card(isLetter: true), Card(isLetter: false), Card(isLetter: false)].shuffled()
        cards = cs
        // initial slots 0,1,2 in current order
        slotFor = Dictionary(uniqueKeysWithValues: cs.enumerated().map { ($0.element.id, $0.offset) })
        
        // 1) brief reveal so they know where the letter begins
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            // 2) flip down & start shuffling with visible swaps
            withAnimation(.easeInOut(duration: 0.22)) { phase = .shuffling }
            startShuffle()
        }
    }
    
    private func startShuffle() {
        // number of visible swaps (random, looks natural)
        var swapsRemaining = Int.random(in: 7...11)
        
        func step() {
            guard swapsRemaining > 0 else {
                // 3) stop and allow exactly one pick
                withAnimation(.easeInOut(duration: 0.2)) { phase = .awaitPick; canPick = true }
                return
            }
            swapsRemaining -= 1
            
            // pick two distinct slots to swap
            let a = Int.random(in: 0...2)
            var b = Int.random(in: 0...2)
            while b == a { b = Int.random(in: 0...2) }
            
            // find the card IDs currently occupying those slots
            guard
                let idA = cards.first(where: { slotFor[$0.id] == a })?.id,
                let idB = cards.first(where: { slotFor[$0.id] == b })?.id
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: step)
                return
            }
            
            // swap their slots → this animates the movement along the track
            slotFor[idA] = b
            slotFor[idB] = a
            
            // cadence between swaps
            let delay = 0.24
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step)
        }
        
        step()
    }
    
    private func pick(slot: Int) {
        guard canPick, pickedSlot == nil else { return }
        pickedSlot = slot
        canPick = false
        
        // which card is at this slot?
        guard let chosenID = cards.first(where: { slotFor[$0.id] == slot })?.id else { return }
        selectedID = chosenID
        
        // animate the selected card itself (pop/bounce) and reveal its face
        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
            phase = .resolving
            selectedScale = 1.12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                selectedScale = 1.0
            }
        }
        
        let pickedIsLetter = cards.first(where: { $0.id == chosenID })?.isLetter ?? false
        
        // close shortly after the reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if pickedIsLetter {
                onDone(.found(seed))
            } else {
                onDone(.nothing)
            }
        }
    }
}

// Simple card face
private struct SingleCardView: View {
    let face: String
    let highlighted: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.dynamicBlack.opacity(0.08))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.dynamicBlack.opacity(0.15))
            Text(face)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.dynamicBlack)
                .scaleEffect(highlighted ? 1.06 : 1.0)
                .shadow(color: .black.opacity(0.35), radius: highlighted ? 6 : 0, y: highlighted ? 2 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: highlighted)
        }
        .frame(width: 86, height: 118)
    }
}

// MARK: - Pop Balloon (colorful, non-overlapping, shows result before close)

struct PopBalloonMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    let letter: Character?
    var onDone: (MiniResult) -> Void
    
    private struct Balloon: Identifiable {
        let id = UUID()
        var center: CGPoint   // container coords (pt)
        var radius: CGFloat
        var color: Color
        var isLetter: Bool
        var glyph: Character   // ← symbol shown BEHIND the balloon
    }
    
    @State private var triesLeft = 3
    @State private var seed: Character = "A"
    @State private var balloons: [Balloon] = []
    @State private var popped: Set<UUID> = []
    @State private var didLayout = false
    
    // result overlay
    @State private var showLetterOverlay: Bool = false
    @State private var showNoLetterOverlay: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tries: \(triesLeft)/3")
                    .font(.caption)
                    .foregroundStyle(Color.dynamicBlack.opacity(0.75))
                Spacer()
                // CountdownPill(deadline: deadline)
            }
            
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.gray.opacity(0.46))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.gray.opacity(0.22)))
                    
                    // ===== symbols layer (BEHIND balloons) =====
                    ForEach(balloons) { b in
                        // sized to stay fully under the balloon so nothing peeks out
                        Text(String(b.glyph))
                            .font(.system(size: b.radius * 1.1, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.dynamicBlack)
                            .opacity(0.95)
                            .position(b.center)
                            .allowsHitTesting(false)
                            .opacity(popped.contains(b.id) ? 1 : 0)
                    }
                    
                    // ===== balloons (cover symbols until popped) =====
                    ForEach(balloons) { b in
                        if !popped.contains(b.id) {
                            BalloonView(color: b.color)
                                .frame(width: b.radius * 2, height: b.radius * 2)
                                .position(b.center)
                                .transition(.scale.combined(with: .opacity))
                                .contentShape(
                                    Circle().path(in: CGRect(x: b.center.x - b.radius,
                                                             y: b.center.y - b.radius,
                                                             width: b.radius * 2,
                                                             height: b.radius * 2))
                                )
                                .onTapGesture { pop(b) }
                                .disabled(showLetterOverlay)
                        }
                    }
                    
                    // ===== result overlays =====
                    if showLetterOverlay {
                        Text(String(seed))
                            .font(.system(size: 72, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.dynamicBlack)
                            .transition(.scale.combined(with: .opacity))
                    } else if showNoLetterOverlay {
                        Text("Letter not found")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.dynamicBlack.opacity(0.9))
                            .transition(.opacity)
                    }
                }
                .onAppear {
                    guard !didLayout else { return }
                    didLayout = true
                    seed = letter ?? hub.pickLetterForOffer()
                    balloons = makePackedBalloons(in: geo.size, countRange: 10...14, seed: seed)
                }
            }
            .frame(height: 260)
        }
    }
    
    // MARK: - Interaction
    
    private func pop(_ b: Balloon) {
        guard triesLeft > 0, !popped.contains(b.id) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            _ = popped.insert(b.id)
        }
        
        if b.isLetter {
            // show letter before closing
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                showLetterOverlay = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                onDone(.found(seed))
            }
        } else {
            triesLeft -= 1
            if triesLeft == 0 {
                // show "Letter not found" before closing
                withAnimation(.easeInOut(duration: 0.25)) { showNoLetterOverlay = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    onDone(.nothing)
                }
            }
        }
    }
    
    // MARK: - Layout: non-overlapping packing + glyphs
    
    private func makePackedBalloons(in size: CGSize, countRange: ClosedRange<Int>, seed: Character) -> [Balloon] {
        var result: [Balloon] = []
        let count = Int.random(in: countRange)
        let edgeInset: CGFloat = 14
        let minR: CGFloat = 18
        let maxR: CGFloat = 30
        let pad: CGFloat = 4   // spacing between balloons
        
        // choose which index will carry the letter
        let letterSlot = Int.random(in: 0..<count)
        var attemptsBudget = 4000
        
        // decoy symbols (avoid the seed if present here)
        var decoys = Array("!@#$%^&*?+-=<>~/\\|").map { Character(String($0)) }.shuffled()
        decoys.removeAll { $0 == seed }
        
        func nextDecoy() -> Character {
            if decoys.isEmpty {
                decoys = Array("!@#$%^&*?+-=<>~/\\|").map { Character(String($0)) }.shuffled()
                decoys.removeAll { $0 == seed }
            }
            return decoys.removeFirst()
        }
        
        func randColor() -> Color {
            // bright, varied palette
            let palette: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .blue, .indigo, .purple, .pink]
            return palette.randomElement()!
        }
        
        while result.count < count && attemptsBudget > 0 {
            attemptsBudget -= 1
            let r = CGFloat.random(in: minR...maxR)
            let x = CGFloat.random(in: (edgeInset + r)...(size.width  - edgeInset - r))
            let y = CGFloat.random(in: (edgeInset + r)...(size.height - edgeInset - r))
            let c = CGPoint(x: x, y: y)
            
            // must not overlap any existing balloon
            let ok = result.allSatisfy { other in
                let d = hypot(c.x - other.center.x, c.y - other.center.y)
                return d >= (r + other.radius + pad)
            }
            if ok {
                let idx = result.count
                let isLetter = idx == letterSlot
                result.append(Balloon(center: c,
                                      radius: r,
                                      color: randColor(),
                                      isLetter: isLetter,
                                      glyph: isLetter ? seed : nextDecoy()))
            }
        }
        
        // ensure at least one letter balloon exists
        if !result.contains(where: { $0.isLetter }), let i = result.indices.randomElement() {
            result[i].isLetter = true
            result[i].glyph = seed
        }
        return result
    }
}

// MARK: - Balloon bubble

private struct BalloonView: View {
    let color: Color
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.dynamicWhite.opacity(0.85),
                            color.opacity(0.95),
                            color.opacity(0.7)
                        ],
                        center: .init(x: 0.35, y: 0.30),
                        startRadius: 2,
                        endRadius: 40
                    )
                )
            // subtle specular highlight
            Circle()
                .stroke(Color.dynamicWhite.opacity(0.35), lineWidth: 1)
                .blur(radius: 0.6)
                .padding(1)
        }
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .contentShape(Circle())
    }
}


// MARK: - Align (no button; auto-detect; freeze on success; reveal before close)

struct SliderAlignMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    let letter: Character?
    var onDone: (MiniResult) -> Void
    
    // MARK: - State
    @State private var seed: Character = "A"
    
    // Playfield
    @State private var fieldSize: CGSize = .zero
    @State private var didSeed = false
    
    // Slider controls ONLY the line height (instant)
    @State private var value: Double = 0.25
    
    // Auto-scanning line (x moves side-to-side)
    @State private var lineX: CGFloat = .zero
    @State private var lineVX: CGFloat = 0    // px/s
    
    // Moving orb
    @State private var dot: CGPoint = .zero
    @State private var vel: CGVector = .zero
    @State private var solved = false
    
    // Reveal overlay
    @State private var showingLetter = false
    @State private var overlayScale: CGFloat = 0.92
    
    // Timing
    @State private var lastTickAt = Date()
    @State private var age: TimeInterval = 0     // seconds since spawn
    private let tick = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    
    // MARK: Tunables
    private let dotR: CGFloat = 10
    private let tipR: CGFloat = 8
    private let lineW: CGFloat = 4
    private let sidePad: CGFloat = 10
    private let topPad: CGFloat = 8
    private let bottomPad: CGFloat = 8
    private let minSpawnGap: CGFloat = 80
    
    // Line horizontal speed (keep it not very fast)
    private let lineSpeed: CGFloat = 95   // px/s
    
    // Orb difficulty
    private let baseSpeedRange: ClosedRange<CGFloat> = 240...320
    private let accelPerSec: CGFloat = 70
    private let jitter: CGFloat = 24
    private let maxSpeed: CGFloat = 480
    
    // Anti-“rush the user” (orb initially repelled from tip)
    private let repelWindow: TimeInterval = 0.90
    private let repelAccel: CGFloat = 340
    
    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                HStack {
                    Text("Raise the line to catch the orb")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    // CountdownPill(deadline: deadline)
                }
                
                // PLAYFIELD
                GeometryReader { geo in
                    let size = geo.size
                    ZStack {
                        // Background
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.dynamicBlack.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.dynamicBlack.opacity(0.10), lineWidth: 1))
                        
                        // Compute tip position (lineX scans horizontally; slider sets height)
                        let usableH = max(0, size.height - topPad - bottomPad - tipR)
                        let tipY = size.height - bottomPad - CGFloat(value) * usableH
                        
                        // Line body
                        Path { p in
                            p.move(to: CGPoint(x: lineX, y: size.height - bottomPad))
                            p.addLine(to: CGPoint(x: lineX, y: tipY))
                        }
                        .stroke(Color.dynamicBlack.opacity(0.9), lineWidth: lineW)
                        
                        // Green tip
                        Circle()
                            .fill(Color.green)
                            .overlay(Circle().stroke(Color.dynamicBlack.opacity(0.85), lineWidth: 1))
                            .frame(width: tipR * 2, height: tipR * 2)
                            .position(x: lineX, y: tipY)
                        
                        // Orb
                        Circle()
                            .fill(Color.yellow)
                            .overlay(Circle().stroke(Color.dynamicBlack.opacity(0.8), lineWidth: 1))
                            .frame(width: dotR * 2, height: dotR * 2)
                            .position(dot)
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    }
                    .onAppear {
                        fieldSize = size
                        // Start the line at center and set slow horizontal motion
                        lineX = size.width * 0.5
                        lineVX = Bool.random() ? lineSpeed : -lineSpeed
                        seedIfNeeded(size: size)
                    }
                    .onChange(of: size) { _, newSize in
                        fieldSize = newSize
                        if !didSeed {
                            lineX = newSize.width * 0.5
                            lineVX = Bool.random() ? lineSpeed : -lineSpeed
                        } else {
                            // keep lineX within bounds if size changed
                            let minX = sidePad
                            let maxX = newSize.width - sidePad
                            lineX = min(max(lineX, minX), maxX)
                        }
                        seedIfNeeded(size: newSize)
                    }
                }
                .frame(height: 230)
                
                // SLIDER (controls the line height only)
                Slider(value: $value, in: 0...1)
                    .disabled(solved)
                    .opacity(solved ? 0.65 : 1)
            }
            
            if showingLetter {
                Text(String(seed))
                    .font(.system(size: 84, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.dynamicBlack)
                    .scaleEffect(overlayScale)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            seed = letter ?? hub.pickLetterForOffer()
            lastTickAt = Date()
            age = 0
        }
        .onReceive(tick) { now in
            guard didSeed, !solved, fieldSize.width > 0, fieldSize.height > 0 else { return }
            let dt = max(0, now.timeIntervalSince(lastTickAt))
            lastTickAt = now
            age += dt
            
            // 1) Move the line side-to-side (bounce at edges)
            advanceLine(dt: dt)
            
            // 2) Advance orb physics
            advanceOrb(dt: dt)
            
            // 3) Collision vs current tip
            let tip = currentTipCenter(in: fieldSize)
            if distance(dot, tip) <= (dotR + tipR) {
                resolve()
            }
        }
        .allowsHitTesting(!solved)
    }
    
    // MARK: - Init / Seeding
    
    private func seedIfNeeded(size: CGSize) {
        guard !didSeed, size.width > 0, size.height > 0 else { return }
        didSeed = true
        age = 0
        
        let tip = currentTipCenter(in: size)
        
        // spawn away from tip
        let minX = sidePad + dotR, maxX = size.width - sidePad - dotR
        let minY = topPad + dotR,  maxY = size.height - bottomPad - dotR
        
        var start = CGPoint(x: .random(in: minX...maxX), y: .random(in: minY...maxY))
        var guardCount = 0
        while distance(start, tip) < minSpawnGap && guardCount < 200 {
            start.x = .random(in: minX...maxX)
            start.y = .random(in: minY...maxY)
            guardCount += 1
        }
        dot = start
        
        // Initial velocity AWAY from the tip
        let speed: CGFloat = .random(in: baseSpeedRange)
        var away = CGVector(dx: start.x - tip.x, dy: start.y - tip.y)
        if away.dx == 0 && away.dy == 0 { away = CGVector(dx: 1, dy: 0) }
        let dirBase = normalized(away)
        let jitterAngle: CGFloat = .random(in: -(.pi/4)...(.pi/4))
        var v = multiply(rotate(dirBase, by: jitterAngle), by: speed)
        
        // If pointing toward tip at all, flip it
        let toTip = CGVector(dx: tip.x - start.x, dy: tip.y - start.y)
        if dot2(v, toTip) > 0 { v.dx = -v.dx; v.dy = -v.dy }
        
        // Ensure both components are meaningful
        if abs(v.dx) < 60 { v.dx = v.dx < 0 ? -60 : 60 }
        if abs(v.dy) < 60 { v.dy = v.dy < 0 ? -60 : 60 }
        
        vel = v
    }
    
    // MARK: - Simulation
    
    private func advanceLine(dt: TimeInterval) {
        guard fieldSize.width > 0 else { return }
        let minX = sidePad
        let maxX = fieldSize.width - sidePad
        
        var x = lineX + lineVX * CGFloat(dt)
        
        if x < minX {
            x = minX + (minX - x)
            lineVX *= -1
        } else if x > maxX {
            x = maxX - (x - maxX)
            lineVX *= -1
        }
        
        lineX = x
    }
    
    private func advanceOrb(dt: TimeInterval) {
        guard dt > 0 else { return }
        var p = dot
        var v = vel
        let size = fieldSize
        
        let minX = sidePad + dotR
        let maxX = size.width - sidePad - dotR
        let minY = topPad + dotR
        let maxY = size.height - bottomPad - dotR
        
        // integrate
        p.x += v.dx * CGFloat(dt)
        p.y += v.dy * CGFloat(dt)
        
        // bounce
        if p.x < minX { p.x = minX + (minX - p.x); v.dx *= -1 }
        else if p.x > maxX { p.x = maxX - (p.x - maxX); v.dx *= -1 }
        
        if p.y < minY { p.y = minY + (minY - p.y); v.dy *= -1 }
        else if p.y > maxY { p.y = maxY - (p.y - maxY); v.dy *= -1 }
        
        // wander + gentle acceleration (hardens over time)
        v.dx += .random(in: -jitter...jitter) * CGFloat(dt)
        v.dy += .random(in: -jitter...jitter) * CGFloat(dt)
        let s = max(1, hypot(v.dx, v.dy))
        v.dx += (v.dx / s) * accelPerSec * CGFloat(dt)
        v.dy += (v.dy / s) * accelPerSec * CGFloat(dt)
        
        // Initial repulsion from current tip
        if age < repelWindow {
            let tip = currentTipCenter(in: size)
            let away = CGVector(dx: p.x - tip.x, dy: p.y - tip.y)
            let n = normalized(away)
            v.dx += n.dx * repelAccel * CGFloat(dt)
            v.dy += n.dy * repelAccel * CGFloat(dt)
        }
        
        // clamp
        let s2 = hypot(v.dx, v.dy)
        if s2 > maxSpeed {
            v.dx = v.dx / s2 * maxSpeed
            v.dy = v.dy / s2 * maxSpeed
        }
        
        dot = p
        vel = v
    }
    
    private func currentTipCenter(in size: CGSize) -> CGPoint {
        let usableH = max(0, size.height - topPad - bottomPad - tipR)
        let tipY = size.height - bottomPad - CGFloat(value) * usableH
        return CGPoint(x: lineX, y: tipY)
    }
    
    // MARK: - Resolve
    
    private func resolve() {
        guard !solved else { return }
        solved = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showingLetter = true
            overlayScale = 1.06
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onDone(.found(seed))
        }
    }
    
    // MARK: - Math
    
    private func normalized(_ v: CGVector) -> CGVector {
        let m = max(0.0001, hypot(v.dx, v.dy))
        return CGVector(dx: v.dx / m, dy: v.dy / m)
    }
    private func rotate(_ v: CGVector, by a: CGFloat) -> CGVector {
        let c = CGFloat(cos(Double(a)))
        let s = CGFloat(sin(Double(a)))
        return CGVector(dx: v.dx * c - v.dy * s,
                        dy: v.dx * s + v.dy * c)
    }
    private func multiply(_ v: CGVector, by k: CGFloat) -> CGVector {
        CGVector(dx: v.dx * k, dy: v.dy * k)
    }
    private func dot2(_ a: CGVector, _ b: CGVector) -> CGFloat { a.dx * b.dx + a.dy * b.dy }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

struct LongPressMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    let letter: Character?
    var onDone: (MiniResult) -> Void
    
    // Gesture / progress
    @GestureState private var pressing = false
    @State private var progress: CGFloat = 0   // 0 → 1 driven explicitly (no auto reverse)
    @State private var finished = false        // locks ring at 1 after success
    
    // Result overlays
    @State private var showLetterOverlay = false
    @State private var showNoLetterOverlay = false
    @State private var seed: Character = "A"
    
    private var hasLetter: Bool { letter != nil } // LongPress is designed to always have a letter, but keep robust
    
    var body: some View {
        let dur: Double = 1.2
        
        // We animate progress ourselves; the gesture just tells us when it succeeded.
        let g = LongPressGesture(minimumDuration: dur)
            .updating($pressing) { isPressing, state, _ in
                state = isPressing
                // Start animating progress only on first touch down.
                if isPressing && progress == 0 && !finished {
                    withAnimation(.linear(duration: dur)) { progress = 1 }
                }
            }
            .onEnded { _ in
                // Success (held full duration)
                guard !finished else { return }
                finished = true              // keep ring at 1; prevents any reverse
                progress = 1                 // ensure fully filled even if small timing drift
                
                if hasLetter {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showLetterOverlay = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        onDone(.found(seed))
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showNoLetterOverlay = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        onDone(.nothing)
                    }
                }
            }
        
        ZStack {
            // Base ring
            Circle()
                .stroke(Color.dynamicBlack.opacity(0.20), lineWidth: 10)
                .frame(width: 120, height: 120)
            
            // Progress ring – driven by `progress` (0→1). No reverse on success because we never set it back.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.dynamicBlack, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 120, height: 120)
            
            // Label fades out when showing a result
            Text("Hold")
                .font(.headline)
                .opacity((showLetterOverlay || showNoLetterOverlay) ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: showLetterOverlay || showNoLetterOverlay)
            
            // Result overlays
            if showLetterOverlay {
                Text(String(seed))
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.dynamicBlack)
                    .transition(.scale.combined(with: .opacity))
            } else if showNoLetterOverlay {
                Text("Letter not found")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.dynamicBlack.opacity(0.95))
                    .transition(.opacity)
            }
        }
        .onAppear { seed = letter ?? hub.pickLetterForOffer() }
        .onChange(of: pressing) { _, nowPressing in
            // If user releases early (didn't meet min duration), softly reset progress.
            if !nowPressing && !finished && progress > 0 && progress < 1 {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .gesture(g)
        .allowsHitTesting(!finished) // lock out extra input once we’ve resolved
        .frame(minHeight: 160)
    }
}

// MARK: - Shake (reveal letter only on success; no pre-letter)

struct ShakeRevealMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    let letter: Character?
    var onDone: (MiniResult) -> Void
    
    private let motion = CMMotionManager()
    @State private var magnitude: Double = 0
    @State private var revealed = false
    @State private var seed: Character = "A"
    
    // visual reveal
    @State private var showingLetter = false
    @State private var letterScale: CGFloat = 0.95
    
    // simple deadline watcher so we close with Letter not found when time is up
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Shake your device").font(.subheadline.weight(.semibold))
                Spacer()
                // CountdownPill(deadline: deadline)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.dynamicBlack.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.dynamicBlack.opacity(0.12)))
                    .frame(height: 140)
                
                if showingLetter {
                    Text(String(seed))
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dynamicBlack)
                        .scaleEffect(letterScale)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    // neutral, non-letter prompt (Letter not found before success)
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(Color.dynamicBlack.opacity(0.85))
                        .accessibilityLabel("Shake to reveal")
                }
            }
        }
        .onAppear {
            seed = letter ?? hub.pickLetterForOffer()
            startAccelerometer()
        }
        .onReceive(tick) { t in
            now = t
            if !revealed && deadline.timeIntervalSince(now) <= 0 {
                stopAccelerometer()
                onDone(.nothing)              // time up → close with Letter not found shown
            }
        }
        .onDisappear { stopAccelerometer() }
    }
    
    // MARK: - Motion
    
    private func startAccelerometer() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1/30
        motion.startAccelerometerUpdates(to: .main) { data, _ in
            guard !revealed, let a = data?.acceleration else { return }
            magnitude = sqrt(a.x*a.x + a.y*a.y + a.z*a.z)
            if magnitude > 2.2 { revealAndClose() }
        }
    }
    
    private func stopAccelerometer() {
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
    }
    
    // MARK: - Reveal flow
    
    private func revealAndClose() {
        guard !revealed else { return }
        revealed = true
        stopAccelerometer()
        
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showingLetter = true
            letterScale = 1.05
        }
        
        // give the player a moment to *see* the letter before closing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onDone(.found(seed))
        }
    }
}

// MARK: - Tap Target (slower, safe start, 3 taps required; reveal before close)
// Disable interactive-pop (edge back swipe) while this mini is on screen.
private struct PopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Controller() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    private final class Controller: UIViewController {
        private weak var popRecognizer: UIGestureRecognizer?
        private var wasEnabled = true
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            popRecognizer = navigationController?.interactivePopGestureRecognizer
            if let g = popRecognizer {
                wasEnabled = g.isEnabled
                g.isEnabled = false
            }
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let g = popRecognizer { g.isEnabled = wasEnabled }
        }
    }
}

struct TapTargetMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    let letter: Character?
    var onDone: (MiniResult) -> Void
    
    // tuning
    private let hitsNeeded = 3
    @State private var interval: TimeInterval = 0.68   // start rate; tightens on each hit
    @State private var radius: CGFloat = 11            // target radius; shrinks on each hit
    private let hitFreeze: TimeInterval = 0.35         // freeze after a hit
    private let respawnGap: TimeInterval = 0.12        // hidden gap before respawn
    private let minDelta: CGFloat = 64                 // min move distance between spawns
    
    // state
    @State private var seeded: Character = "A"
    @State private var area: CGSize = .zero
    @State private var pos: CGPoint = .zero
    @State private var visible = false
    @State private var hits = 0
    @State private var finished = false
    @State private var tapFlash = false
    @State private var paused = false                  // pauses the move loop cleanly
    @State private var moveTask: Task<Void, Never>?    // replaces Timer → no race
    
    // tap indication
    private struct Pulse: Identifiable { let id = UUID(); let center: CGPoint; let start = Date() }
    @State private var pulses: [Pulse] = []
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Taps: \(hits)/\(hitsNeeded)")
                    .font(.caption)
                    .foregroundStyle(Color.dynamicBlack.opacity(0.75))
                Spacer()
                // CountdownPill(deadline: deadline)
            }
            
            GeometryReader { geo in
                ZStack {
                    // block edge-swipes while we’re active
                    PopGestureDisabler().frame(width: 0, height: 0).hidden()
                    
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.dynamicBlack.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.dynamicBlack.opacity(0.12)))
                    
                    // animated ripple indication
                    TimelineView(.animation) { tl in
                        Canvas { ctx, size in
                            let now = tl.date
                            for p in pulses {
                                let t = now.timeIntervalSince(p.start)
                                guard t <= 0.6 else { continue }
                                let prog = max(0, min(1, t / 0.6))
                                let r = radius + CGFloat(10 + 120 * prog)
                                let a = Double(1 - prog)
                                let rect = CGRect(x: p.center.x - r, y: p.center.y - r, width: r*2, height: r*2)
                                ctx.stroke(Circle().path(in: rect),
                                           with: .color(Color.dynamicBlack.opacity(0.35 * a)),
                                           lineWidth: 2)
                            }
                        }
                    }
                    
                    if visible && !finished {
                        Circle()
                            .fill(tapFlash ? PremiumPalette.accent : Color.dynamicBlack)
                            .frame(width: radius * 2, height: radius * 2)
                            .position(pos)
                            .scaleEffect(tapFlash ? 1.25 : 1.0)
                            .shadow(color: Color.dynamicBlack.opacity(tapFlash ? 0.6 : 0), radius: 6, y: 2)
                            .animation(.easeOut(duration: 0.18), value: tapFlash)
                            .transition(.scale.combined(with: .opacity))
                            .contentShape(Circle())
                            .highPriorityGesture( // ensure our tap wins
                                TapGesture().onEnded { handleTap() }
                            )
                    }
                    
                    // final letter overlay
                    if finished {
                        Text(String(seeded))
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.dynamicBlack)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .onAppear {
                    area = geo.size
                    seeded = letter ?? hub.pickLetterForOffer()
                    pos = randomPos(in: area, margin: max(40, radius + 20))
                    visible = true
                    startMoveLoop()
                }
                .onChange(of: geo.size) { _, new in area = new }
                .onDisappear { stopMoveLoop() }
            }
            .frame(height: 180)
        }
    }
    
    // MARK: - Tap handling (no race)
    private func handleTap() {
        guard !finished else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // flash + ripple
        tapFlash = true
        pulses.append(Pulse(center: pos))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { tapFlash = false }
        // prevent the move loop from toggling visibility during this whole flow
        paused = true
        // force visible immediately in case the loop just hid it on the same tick
        withTransaction(Transaction(animation: nil)) { visible = true }
        
        hits += 1
        if hits >= hitsNeeded {
            finishSuccess()
            return
        }
        
        // tighten difficulty for next rounds
        interval = max(0.54, interval * 0.86)
        radius   = max(9, radius - 1.0)
        pulses.removeAll { Date().timeIntervalSince($0.start) > 0.6 }
        
        // freeze → hide → move → show → resume (all without the timer)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(hitFreeze * 1_000_000_000))
            withAnimation(.easeInOut(duration: 0.16)) { visible = false }
            let newPos = randomPos(in: area, margin: max(36, radius + 18), awayFrom: pos, minDelta: minDelta)
            pos = newPos
            try? await Task.sleep(nanoseconds: UInt64(respawnGap * 1_000_000_000))
            withAnimation(.easeInOut(duration: 0.18)) { visible = true }
            paused = false
        }
    }
    
    // MARK: - Movement loop (Task-based; easy to pause/cancel)
    private func startMoveLoop() {
        stopMoveLoop()
        moveTask = Task { @MainActor in
            while !Task.isCancelled && !finished {
                let wait = interval
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled || finished || paused { continue }
                withAnimation(.easeInOut(duration: 0.18)) {
                    visible.toggle()
                    if visible {
                        pos = randomPos(in: area, margin: max(36, radius + 18), awayFrom: pos, minDelta: minDelta)
                    }
                }
            }
        }
    }
    
    private func stopMoveLoop() {
        moveTask?.cancel()
        moveTask = nil
    }
    
    // MARK: - Success flow
    private func finishSuccess() {
        finished = true
        paused = true
        stopMoveLoop()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            visible = false
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            // show the letter overlay
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onDone(.found(seeded))
        }
    }
    
    // MARK: - Positioning
    private func randomPos(in size: CGSize, margin: CGFloat, awayFrom last: CGPoint? = nil, minDelta: CGFloat = 0) -> CGPoint {
        var p: CGPoint = .zero
        var tries = 0
        repeat {
            tries += 1
            p = CGPoint(x: .random(in: margin...(size.width  - margin)),
                        y: .random(in: margin...(size.height - margin)))
            if last == nil {
                // bias first spawn a bit toward center (avoid corners)
                let cx = size.width * 0.5, cy = size.height * 0.5
                let t: CGFloat = 0.28
                p.x = p.x * (1 - t) + cx * t
                p.y = p.y * (1 - t) + cy * t
            }
        } while (last.map { hypot(p.x - $0.x, p.y - $0.y) < minDelta } ?? false) && tries < 12
        return p
    }
}
