import Foundation
import SwiftUI

// MARK: - Transient seam light that spreads then fades out
public struct LightLeakConfig {
    public var enabled: Bool
    public var tint: Color            // seam light color
    public var minWidth: CGFloat      // seam width at p=0
    public var maxWidth: CGFloat      // seam width at p=1 (spread)
    public var maxOpacity: Double     // peak opacity (occurs during opening, not at 1.0)
    public var baseline: Double       // tiny glow when closed; auto-fades to 0 as p→1
    public var blur: CGFloat          // softness across seam
    public var cornerLeak: Bool       // tiny top/bottom bursts
    public var skew: CGFloat          // >1 peak later, <1 peak earlier (1 = mid)
    public var shapePower: CGFloat    // bell sharpness (1..3 typical)
    
    public init(
        enabled: Bool = false,
        tint: Color = .white,
        minWidth: CGFloat = 1,
        maxWidth: CGFloat = 22,
        maxOpacity: Double = 0.28,
        baseline: Double = 0.05,
        blur: CGFloat = 10,
        cornerLeak: Bool = true,
        skew: CGFloat = 1.0,
        shapePower: CGFloat = 1.6
    ) {
        self.enabled = enabled
        self.tint = tint
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.maxOpacity = maxOpacity
        self.baseline = baseline
        self.blur = blur
        self.cornerLeak = cornerLeak
        self.skew = skew
        self.shapePower = shapePower
    }
    
    public static let disabled = LightLeakConfig()
    
    /// Subtle, cinematic default
    public static func subtleSpread(
        tint: Color = .white,
        maxOpacity: Double = 0.76,
        minWidth: CGFloat = 1,
        maxWidth: CGFloat = 300,
        blur: CGFloat = 30,
        cornerLeak: Bool = true
    ) -> LightLeakConfig {
        .init(
            enabled: true,
            tint: tint,
            minWidth: minWidth,
            maxWidth: maxWidth,
            maxOpacity: maxOpacity,
            baseline: 0.05,
            blur: blur,
            cornerLeak: cornerLeak,
            skew: 1.0,          // peak at ~50% open
            shapePower: 1.6     // smooth bell
        )
    }
}

// MARK: - Seam light that spreads then fades (intensity ~ sin(pi*t)^shape)
private struct LightLeakOverlay: View {
    let progress: CGFloat          // 0…1 door open progress
    let config: LightLeakConfig
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let t = clamp(progress, 0, 1)
            
            // Skew the timeline so the peak can be earlier/later than 50%
            let tSkew = pow(t, max(0.0001, config.skew))
            
            // Bell-shaped intensity: 0 at 0, peaks mid, 0 at 1
            let bell = pow(sin(.pi * Double(tSkew)), Double(config.shapePower)) // 0..1..0
            // Baseline softly present near closed, auto-removed by (1 - t)
            let base = config.baseline * Double(1 - t)
            let opacity = min(1.0, base + bell * config.maxOpacity)
            
            // Seam width grows with progress (spreads), even as opacity later fades
            let width = lerp(config.minWidth, config.maxWidth, easeOutCubic(t))
            
            ZStack {
                // Vertical glow band centered at seam
                LinearGradient(
                    colors: [
                        config.tint.opacity(opacity * 0.10),
                        config.tint.opacity(opacity),
                        config.tint.opacity(opacity * 0.10),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: max(1, width))
                .blur(radius: config.blur)
                .blendMode(.screen)
                
                // Knife-edge at the very center for realism
                Rectangle()
                    .fill(config.tint.opacity(opacity * 1.1))
                    .frame(width: max(1, width * 0.22))
                    .blur(radius: 1.4)
                    .blendMode(.screen)
                
                if config.cornerLeak && width > 4 {
                    // Tiny top and bottom “escape” bursts
                    let burstOpacity = opacity * 0.45
                    RadialGradient(
                        colors: [config.tint.opacity(burstOpacity),
                                 config.tint.opacity(opacity * 0.12),
                                 .clear],
                        center: .center, startRadius: 2, endRadius: min(w, h) * 0.18
                    )
                    .frame(width: width * 6, height: width * 6)
                    .offset(y: -h * 0.42)
                    .blendMode(.screen)
                    .blur(radius: config.blur * 0.7)
                    
                    RadialGradient(
                        colors: [config.tint.opacity(burstOpacity),
                                 config.tint.opacity(opacity * 0.12),
                                 .clear],
                        center: .center, startRadius: 2, endRadius: min(w, h) * 0.18
                    )
                    .frame(width: width * 6, height: width * 6)
                    .offset(y:  h * 0.42)
                    .blendMode(.screen)
                    .blur(radius: config.blur * 0.7)
                }
            }
            .frame(width: w, height: h)
            .position(x: w/2, y: h/2)
        }
        .allowsHitTesting(false)
    }
    
    // Helpers
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    private func easeOutCubic(_ t: CGFloat) -> CGFloat { let u = 1 - t; return 1 - u*u*u }
    private func clamp(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max(x, a), b) }
}

public struct SlidingDoorOpen<Content: View>: View {
    public enum OpenMode { case gap(spacing: CGFloat = 8), offscreen(edgePadding: CGFloat = 12) }
    
    @Binding private var isOpen: Bool
    private let shimmer: Bool
    private let durationInner: Double
    private let textInner: String
    private let delayInner: Double
    private let tilt: Double
    private let cornerRadius: CGFloat
    private let allowDragToOpen: Bool
    private let openMode: OpenMode
    private let stagger: Double
    private let contentDelay: Double
    private let content: Content
    
    // NEW: transient seam light
    private let lightLeak: LightLeakConfig
    
    private var duration: Double { durationInner }
    private var delay: Double { delayInner }
    private var text: String { textInner }
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(
        isOpen: Binding<Bool>,
        shimmer: Bool,
        text: String = "",
        duration: Double = 1.2,
        delay: Double = 0.05,
        tilt: Double = 14,
        cornerRadius: CGFloat = 14,
        allowDragToOpen: Bool = false,
        openMode: OpenMode = .offscreen(edgePadding: 12),
        stagger: Double = 0.0,
        contentDelay: Double = 0.0,
        lightLeak: LightLeakConfig = .disabled,     // <— NEW
        @ViewBuilder content: () -> Content
    ) {
        self._isOpen = isOpen
        self.shimmer = shimmer
        self.textInner = text.localized
        self.durationInner = duration
        self.delayInner = delay
        self.tilt = tilt
        self.cornerRadius = cornerRadius
        self.allowDragToOpen = allowDragToOpen
        self.openMode = openMode
        self.stagger = stagger
        self.contentDelay = contentDelay
        self.lightLeak = lightLeak
        self.content = content()
    }
    
    @State private var dragProgress: CGFloat = 0
    
    public var body: some View {
        let W = UIScreen.main.bounds.width
        let H = UIScreen.main.bounds.height
        let half = W / 2
        
        // 0..1 progress (includes gesture contribution)
        let baseProgress: CGFloat = isOpen ? 1 : 0
        let p = min(max(baseProgress + dragProgress, 0), 1)
        
        // how far each door travels
        let travel: CGFloat = {
            switch openMode {
            case .gap(let spacing):        return half + spacing / 2
            case .offscreen(let padding):  return W + padding
            }
        }()
        
        let baseAnim = Animation.easeInOut(duration: reduceMotion ? 0 : duration)
        let leftDelay  = reduceMotion ? 0 : delay
        let rightDelay = reduceMotion ? 0 : (delay + stagger)
        
        ZStack {
            // Content with subtle “closed” vignette
            content
                .padding(.vertical, 40)
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.35 * (1 - p)), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .blur(radius: (1 - p) * 2)
                .animation(baseAnim.delay(reduceMotion ? 0 : contentDelay), value: isOpen)
            
            // Doors
            let comps = componnets()
            let start = comps.start
            let end   = comps.end
            
            HStack(spacing: 0) {
                door(left: true, width: half, height: H, text: start, progress: p)
                    .offset(x: -travel * p)
                    .rotation3DEffect(.degrees(Double(-tilt) * p),
                                      axis: (x: 0, y: 1, z: 0),
                                      anchor: .trailing,
                                      perspective: 0.8)
                    .animation(baseAnim.delay(leftDelay), value: isOpen)
                
                door(left: false, width: half, height: H, text: end, progress: p)
                    .offset(x:  travel * p)
                    .rotation3DEffect(.degrees(Double(tilt) * p),
                                      axis: (x: 0, y: 1, z: 0),
                                      anchor: .leading,
                                      perspective: 0.8)
                    .animation(baseAnim.delay(rightDelay), value: isOpen)
            }
            .allowsHitTesting(!isOpen)
            .ignoresSafeArea()
            
            // Transient seam light ABOVE the doors
            if lightLeak.enabled {
                LightLeakOverlay(progress: p, config: lightLeak)
                    .ignoresSafeArea()
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture(width: W), including: allowDragToOpen ? .all : .subviews)
        .onChange(of: isOpen) {
            withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.25)) {
                dragProgress = 0
            }
        }
    }
    
    private func componnets() -> (start: String, end: String) {
        if text.count >= 2 {
            let parts = text.components(separatedBy: .whitespaces)
            let start = parts[0].trimLeadingAndTrailingSpacesAndNewlines()
            let end   = parts.dropFirst().joined(separator: " ").trimLeadingAndTrailingSpacesAndNewlines()
            return (start, end)
        }
        return ("", "")
    }
    
    private func door(left: Bool, width: CGFloat, height: CGFloat, text: String = "", progress p: CGFloat) -> some View {
        ZStack(alignment: left ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(doorMaterial(left: left).opacity(0.88))
                .realStone(cornerRadius: cornerRadius, left: left)
                .background(.ultraThickMaterial)
            
            DoorOrnamentsView(cornerRadius: cornerRadius,
                              shimmer: shimmer,
                              side: left ? .left : .right,
                              openProgress: p)
            
            DebossedText(text: text)
                .padding(left ? .trailing : .leading, UIDevice.current.userInterfaceIdiom == .pad ? 94 : 74)
                .padding(.bottom, 2.5)
        }
        .frame(width: width, height: height)
        .cornerRadius(cornerRadius)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    
    private func doorMaterial(left: Bool) -> some ShapeStyle {
        LinearGradient(
            colors: left
            ? [Color(.systemGray3).opacity(0.98),
               Color(.systemGray3).opacity(0.95),
               Color(.systemGray3).opacity(0.92)]
            : [Color(.systemGray3).opacity(0.92),
               Color(.systemGray3).opacity(0.95),
               Color(.systemGray3).opacity(0.98)],
            startPoint: left ? .topLeading : .bottomTrailing,
            endPoint:   left ? .bottomTrailing : .topLeading
        )
    }
    
    private func dragGesture(width W: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard allowDragToOpen else { return }
                let fromCenterX = value.location.x - (W/2)
                let delta = value.translation.width
                let dirOK = (fromCenterX < 0 && delta < 0) || (fromCenterX > 0 && delta > 0)
                if dirOK {
                    let prog = min(1, max(0, abs(delta) / (W * 0.35)))
                    dragProgress = prog * (isOpen ? 0 : 1)
                }
            }
            .onEnded { value in
                guard allowDragToOpen else { return }
                let threshold: CGFloat = 0.28
                let dragAmount = min(1, max(0, abs(value.translation.width) / (W * 0.35)))
                withAnimation(.easeInOut(duration: reduceMotion ? 0 : duration)) {
                    if !isOpen { isOpen = dragAmount > threshold }
                }
                dragProgress = 0
            }
    }
}

// MARK: - Convenience clamp
private func clamp(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max(x, a), b) }

// ===============================
// MARK: String helpers (unchanged)
// ===============================
public extension String {
    func substring(to end: Int) -> String {
        guard end > 0 else { return "" }
        let c = count
        let endClamped = min(end, c)
        let endIdx = index(startIndex, offsetBy: endClamped)
        return String(self[..<endIdx])
    }
    func substring(from start: Int) -> String {
        let c = count
        guard start < c else { return "" }
        let startClamped = max(0, start)
        let startIdx = index(startIndex, offsetBy: startClamped)
        return String(self[startIdx...])
    }
    func substring(_ range: Range<Int>) -> String {
        let c = count
        let lower = max(0, min(range.lowerBound, c))
        let upper = max(0, min(range.upperBound, c))
        guard lower < upper else { return "" }
        let startIdx = index(startIndex, offsetBy: lower)
        let endIdx   = index(startIndex, offsetBy: upper)
        return String(self[startIdx..<endIdx])
    }
    subscript(_ range: Range<Int>) -> String { substring(range) }
    subscript(_ range: ClosedRange<Int>) -> String {
        let c = count; guard !isEmpty else { return "" }
        let lower = max(0, min(range.lowerBound, c - 1))
        let upper = max(0, min(range.upperBound, c - 1))
        guard lower <= upper else { return "" }
        let startIdx = index(startIndex, offsetBy: lower)
        let endIdx   = index(startIndex, offsetBy: upper)
        let afterEnd = index(after: endIdx)
        return String(self[startIdx..<afterEnd])
    }
    subscript(_ range: PartialRangeFrom<Int>) -> String { substring(from: range.lowerBound) }
    subscript(_ range: PartialRangeUpTo<Int>) -> String { substring(to: range.upperBound) }
    subscript(_ range: PartialRangeThrough<Int>) -> String {
        let c = count; guard c > 0 else { return "" }
        let upper = min(max(range.upperBound, 0), c - 1)
        return self[0...upper]
    }
}

public extension String {
    private static let spaceNewlineSet: CharacterSet = {
        var s = CharacterSet(); s.insert(charactersIn: " \n\r"); return s
    }()
    func trimmingSpacesAndNewlines() -> String {
        trimmingCharacters(in: Self.spaceNewlineSet)
    }
    func trimmingLeadingSpacesAndNewlines() -> String {
        guard let start = rangeOfCharacter(from: Self.spaceNewlineSet.inverted)?.lowerBound else { return "" }
        return String(self[start...])
    }
    func trimmingTrailingSpacesAndNewlines() -> String {
        guard let end = rangeOfCharacter(from: Self.spaceNewlineSet.inverted, options: .backwards)?.upperBound else { return "" }
        return String(self[..<end])
    }
    func trimLeadingAndTrailingSpacesAndNewlines() -> String {
        trimmingLeadingSpacesAndNewlines().trimmingTrailingSpacesAndNewlines()
    }
    mutating func trimSpacesAndNewlines()                   { self = trimmingSpacesAndNewlines() }
    mutating func trimLeadingSpacesAndNewlines()            { self = trimmingLeadingSpacesAndNewlines() }
    mutating func trimTrailingSpacesAndNewlines()           { self = trimmingTrailingSpacesAndNewlines() }
    mutating func trimLeadingAndTrailingSpacesAndNewlines() { self = trimLeadingAndTrailingSpacesAndNewlines() }
}

// ==================================
// MARK: Debossed label (pro palette)
// ==================================
struct DebossedText: View {
    let text: String
    var font: Font = .system(size: 16, weight: .heavy, design: .rounded)
    var depth: CGFloat = 1.5
    var blur: CGFloat = 1.4
    
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        let dark  = scheme == .dark ? Gold.deep : Gold.mid.opacity(0.85)
        let light = scheme == .dark ? Gold.hi   : Gold.hi.opacity(0.95)
        
        ZStack {
            Text(text)
                .font(font)
                .foregroundStyle(.primary.opacity(scheme == .dark ? 0.80 : 0.85))
            
            Text(text)
                .font(font)
                .foregroundStyle(dark)
                .offset(x: depth, y: depth)
                .blur(radius: blur)
                .mask(Text(text).font(font))
                .blendMode(.multiply)
            
            Text(text)
                .font(font)
                .foregroundStyle(light)
                .offset(x: -depth, y: -depth)
                .blur(radius: blur)
                .mask(Text(text).font(font))
                .blendMode(.screen)
        }
        .compositingGroup()
        .accessibilityLabel(text)
    }
}

// Subtle metal sheen used on door panels
private struct NoiseMetalSheen: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            AngularGradient(
                gradient: Gradient(stops: [
                    .init(color: .white.opacity(0.02), location: 0.00),
                    .init(color: .black.opacity(0.02), location: 0.25),
                    .init(color: .white.opacity(0.02), location: 0.50),
                    .init(color: .black.opacity(0.02), location: 0.75),
                    .init(color: .white.opacity(0.02), location: 1.00)
                ]),
                center: .center
            )
            .blendMode(.overlay)
            
            LinearGradient(
                colors: [
                    .white.opacity(scheme == .dark ? 0.10 : 0.07),
                    .clear,
                    .white.opacity(scheme == .dark ? 0.08 : 0.05)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .blendMode(.screen)
        }
        .compositingGroup()
    }
}
