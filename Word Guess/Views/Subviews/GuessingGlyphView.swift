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
    public var holdStagger: TimeInterval = 0.08        // extra delay per *visual* index
    public var holdGlyph: String = "?"
    
    // NEW: wave direction control
    public var waveDirection: WaveDirection = .autoByLayout
    
    @State private var appearDate: Date = .distantPast
    @Environment(\.layoutDirection) private var layoutDirection
    
    public init(index: Int,
                outOf stringLangth: Int,
                language: Language,
                staggerFraction: Double = 0.18,
                changesPerSecond: Double = 1.2,
                fontSize: CGFloat = 18,
                weight: Font.Weight = .medium,
                initialHoldDuration: TimeInterval = 2.2,
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
        case .autoByLayout:
            // reading order (works for LTR and RTL automatically)
            return index
            
        case .leftToRight:
            // physical left → right, regardless of locale
            return (layoutDirection == .rightToLeft) ? (stringLangth - 1 - index) : index
            
        case .rightToLeft:
            // physical right → left, regardless of locale
            return (layoutDirection == .rightToLeft) ? index : (stringLangth - 1 - index)
        }
    }
    
    public var body: some View {
        let period = self.period
        let offset = Double(index) * period * staggerFraction
        let localHold = initialHoldDuration + holdStagger * Double(visualIndex)
        
        TimelineView(.periodic(from: .now, by: period)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(appearDate))
            
            if elapsed < localHold {
                // --- glitchy “?” hold (kept subtle & centered) ---
                let t = elapsed
                let frame = Int(floor(t * 30))
                let jx = CGFloat(sin(t * 17) * 0.4 + cos(t * 11) * 0.3)
                let jy = CGFloat(cos(t * 13) * 0.35 + sin(t * 19) * 0.25)
                let spike = (frame % 37 == 0) ? 1.6 : 0.0
                let chroma: CGFloat = 0.6 + (spike > 0 ? 0.9 : 0)
                let scale = 1.0 + 0.006 * sin(t * 41)
                let rot = Angle.degrees(0.28 * sin(t * 53))
                
                ZStack {
                    baseStyledText(holdGlyph)
                        .scaleEffect(scale)
                        .rotationEffect(rot)
                    
                    Text(holdGlyph)
                        .font(.system(size: fontSize, weight: weight, design: .rounded))
                        .foregroundColor(.red.opacity(0.18))
                        .blendMode(.plusLighter)
                        .offset(x: jx + chroma + spike, y: jy)
                    
                    Text(holdGlyph)
                        .font(.system(size: fontSize, weight: weight, design: .rounded))
                        .foregroundColor(.cyan.opacity(0.18))
                        .blendMode(.plusLighter)
                        .offset(x: jx - chroma - spike, y: jy)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                
            } else {
                // --- main animation ---
                let t = (elapsed - localHold) + offset
                let step  = Int(floor(t / period))
                let phase = (t / period).truncatingRemainder(dividingBy: 1)
                
                let base   = Int(truncatingIfNeeded: step &* 1103515245 &+ 12345)
                let salt   = (index &* 9973 &+ 2713) % max(glyphs.count, 1)
                let idxRaw = (abs(base) &+ salt) % max(glyphs.count, 1)
                let glyphSymbol  = glyphs[idxRaw].returnChar(isFinal: index == stringLangth - 1)
                let glyph = index == 0 ? glyphSymbol.capitalizedFirst : glyphSymbol
                
                let eased = phase * phase * (3 - 2 * phase)
                let angle = Angle.degrees(10 * sin(eased * 2 * .pi))
                let scale = 1.0 + 0.03 * sin(eased * 2 * .pi)
                
                baseStyledText(glyph)
                    .scaleEffect(scale)
                    .rotation3DEffect(angle, axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                    .animation(.easeInOut(duration: period), value: step)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onAppear { appearDate = Date() }
        .accessibilityLabel("Guessing glyph animation")
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
}

// MARK: - Palette & Glyphs
public extension GuessingGlyphView {
    static func defaultGlyphs(language: Language) -> [String] {
        let letters = Array(language == .en
                            ? "abcdefghijklmnopqrstuvwxyz"
                            : "אבגדלהוזחטיכלמנסעפצקרשת").map { String($0) }
        //        let numbers = Array("0123456789").map { String($0) }
        //        let symbols = [
        //            "★","☆","✦","✧","✪","✬","✯","◆","◇","◈",
        //            "♠︎","♣︎","♥︎","♦︎","☯︎","☢︎","☣︎","∞","⌘","⌁",
        //            "✺","✹","✸","✷","▣","▤","▥","▦","▧","▨","▩",
        //            "░","▒","▓","█","▞","▚","▟","▙","▛","▜",
        //            "◉","◎","●","◍","◐","◑","◒","◓","◔","◕"
        //        ]
        return letters /*+ numbers + symbols*/
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
