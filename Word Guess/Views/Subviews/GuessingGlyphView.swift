import SwiftUI

public enum WaveDirection {
    case autoByLayout            // uses \.layoutDirection (default)
    case leftToRight
    case rightToLeft
}

public struct GuessingGlyphView: View {
    public let index: Int
    public let stringLangth: Int
    
    // Motion & look
    public var staggerFraction: Double = 0.18
    public var changesPerSecond: Double = 3
    public var fontSize: CGFloat = 26
    public var weight: Font.Weight = .medium
    
    // Glyphs
    public var glyphs: [String]
    
    // Hold phase
    public var initialHoldDuration: TimeInterval = 1.0
    public var holdStagger: TimeInterval = 0.2        // extra delay per *visual* index
    public var holdGlyph: String = "?"
    
    // NEW: wave direction control
    public var waveDirection: WaveDirection = .autoByLayout
    
    @State private var appearDate: Date = .distantPast
    @Environment(\.layoutDirection) private var layoutDirection
    
    public init(index: Int,
                outOf stringLangth: Int,
                language: Language,
                staggerFraction: Double = 0.18,
                changesPerSecond: Double = 3,
                fontSize: CGFloat = 18,
                weight: Font.Weight = .medium,
                initialHoldDuration: TimeInterval = 2.4,
                holdStagger: TimeInterval = 0.12,
                holdGlyph: String = "?",
                waveDirection: WaveDirection = .autoByLayout) {
        self.index = index
        self.stringLangth = stringLangth
        self.staggerFraction = staggerFraction
        self.changesPerSecond = changesPerSecond
        self.fontSize = fontSize
        self.weight = weight
        self.initialHoldDuration = initialHoldDuration
        self.holdStagger = holdStagger
        self.holdGlyph = holdGlyph
        self.waveDirection = waveDirection
        self.glyphs = Self.defaultGlyphs(language: language)
    }
    
    private var period: TimeInterval { max(0.02, 1.0 / changesPerSecond) }
    
    // Visual index = the order the user *sees* (LTR or RTL)
    // Visual rank used for the "?" hold staggering
    private var visualIndex: Int {
        guard stringLangth > 0 else { return index }
        switch waveDirection {
        case .autoByLayout: return index
        case .leftToRight: return (layoutDirection == .rightToLeft) ? (stringLangth - 1 - index) : index
        case .rightToLeft: return (layoutDirection == .rightToLeft) ? index : (stringLangth - 1 - index)
        }
    }
    
    public var body: some View {
        let period = self.period
        let offset = Double(index) * period * staggerFraction
        let localHold = initialHoldDuration + holdStagger * Double(visualIndex)
        
        TimelineView(.periodic(from: .now, by: period / 90.0)) { context in
            // small tick granularity for smoother in-between progress
            let elapsed = max(0, context.date.timeIntervalSince(appearDate))
            
            if elapsed < localHold {
                ZStack {
                    baseStyledText(holdGlyph)
                    
                    Text(holdGlyph)
                        .font(.system(size: fontSize, weight: weight, design: .rounded))
                        .foregroundColor(.red.opacity(0.18))
                        .blendMode(.plusLighter)
                    
                    Text(holdGlyph)
                        .font(.system(size: fontSize, weight: weight, design: .rounded))
                        .foregroundColor(.cyan.opacity(0.18))
                        .blendMode(.plusLighter)
                }
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .center)
            } else {
                // --- main animation with morphing ---
                let tAll    = (elapsed - localHold) + offset
                let stepF   = tAll / period
                let step    = Int(floor(stepF))
                let frac    = stepF - floor(stepF)   // 0 → 1 within current period
                
                let prevIdx = idx(for: step - 1)
                let currIdx = idx(for: step)
                
                let prevRaw = glyphs[prevIdx].returnChar(isFinal: index == stringLangth - 1)
                let currRaw = glyphs[currIdx].returnChar(isFinal: index == stringLangth - 1)
                
                let prev = index == 0 ? prevRaw.capitalizedFirst : prevRaw
                let curr = index == 0 ? currRaw.capitalizedFirst : currRaw
                
                MorphStack(
                    from: prev,
                    to: curr,
                    progress: smoothStep(frac),     // eased progress for nicer feel
                    fontSize: fontSize,
                    weight: weight,
                    baseStyled: baseStyledText
                )
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .center)
                .accessibilityLabel("Guessing glyph animation")
            }
        }
        .onAppear { appearDate = Date() }
    }
    
    // Deterministic index for a given step
    private func idx(for s: Int) -> Int {
        let base = Int(truncatingIfNeeded: s &* 1103515245 &+ 12345)
        let salt = (index &* 9973 &+ 2713) % max(glyphs.count, 1)
        return (abs(base) &+ salt) % max(glyphs.count, 1)
    }
    
    // MARK: styled text
    private func baseStyledText(_ glyph: String) -> some View {
        Text(glyph)
            .font(.system(size: fontSize, weight: weight, design: .rounded))
            .foregroundStyle(Self.placeholderBase)
            .shadow(color: Self.placeholderOutline, radius: 0.6)
            .shadow(color: Self.placeholderOutline, radius: 1.2)
            .overlay(
                Text(glyph)
                    .font(.system(size: fontSize, weight: weight, design: .rounded))
                    .foregroundStyle(Self.neon)
                    .opacity(0.20)
                    .blendMode(.screen)
            )
    }
    
    // Hermite smoothstep for nicer interpolation
    private func smoothStep(_ x: Double) -> Double {
        let t = max(0, min(1, x))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Morphing Layer
private struct MorphStack<BaseStyled: View>: View {
    let from: String
    let to: String
    let progress: Double
    let fontSize: CGFloat
    let weight: Font.Weight
    let baseStyled: (String) -> BaseStyled
    
    var body: some View {
        ZStack {
            // Previous glyph fades out
            baseStyled(from)
                .opacity(1.0 - progress)
                .allowsHitTesting(false)
            
            // Next glyph fades in
            baseStyled(to)
                .opacity(progress)
                .allowsHitTesting(false)
        }
        // No implicit animations; progress is driven by TimelineView ticks
    }
}

// MARK: - Palette & Glyphs
public extension GuessingGlyphView {
    static func defaultGlyphs(language: Language) -> [String] {
        let letters = Array(language == .en
                            ? "abcdefghijklmnopqrstuvwxyz"
                            : "אבגדלהוזחטיכלמנסעפצקרשת").map { String($0) }
        return letters
    }
    
    static var placeholderBase: Color { Color(white: 0.25).opacity(0.42) }
    static var placeholderOutline: Color { Color(white: 0.0).opacity(0.12) }
    
    static var neon: LinearGradient {
        let edgeA = Color(white: 0.74)
        let mid1  = Color(white: 0.97)
        let mid2  = Color(white: 0.98)
        let edgeB = Color(white: 0.72)
        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: edgeA.opacity(0.22), location: 0.00),
                .init(color: mid1.opacity(0.06),   location: 0.46),
                .init(color: mid2.opacity(0.04),   location: 0.54),
                .init(color: edgeB.opacity(0.22),  location: 1.00)
            ]),
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
