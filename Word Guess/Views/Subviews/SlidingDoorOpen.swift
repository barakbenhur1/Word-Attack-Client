import SwiftUI

/// SlidingDoorOpen: A reusable “sliding door” open/close animation.
/// - Two panels meet at the center when closed and slide outward to reveal the content.
/// - Optional 3D hinge tilt, shadows, and interactive drag-to-open.
/// - Works in light/dark mode; respects Reduce Motion.
public struct SlidingDoorOpen<Content: View>: View {
    public enum OpenMode {
        /// Leaves a visible seam between doors when open
        case gap(spacing: CGFloat = 8)
        /// Slides doors completely offscreen; `edgePadding` lets you overshoot slightly to avoid a sliver on some layouts
        case offscreen(edgePadding: CGFloat = 12)
    }
    
    @Binding private var isOpen: Bool
    private let shimmer: Bool
    private let durationInner: Double
    private let textInner: String
    private let delayInner: Double                 // base delay for both doors
    private let tilt: Double
    private let cornerRadius: CGFloat
    private let allowDragToOpen: Bool
    private let openMode: OpenMode
    private let stagger: Double               // extra delay for the RIGHT door
    private let contentDelay: Double          // delay for content’s overlay/blur animations
    private let content: Content
    
    private var duration: Double { durationInner }
    private var delay: Double { delayInner }
    private var text: String { textInner }
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
        
    /// Init
    /// - Parameters:
    ///   - isOpen: Binding that controls whether the doors are open.
    ///   - duration: Base animation duration (ignored when Reduce Motion is on).
    ///   - delay: Delay before doors start moving (applied to left door).
    ///   - tilt: Degrees of Y-rotation applied as the doors open (0 = flat slide).
    ///   - cornerRadius: Door corner radius.
    ///   - showsInnerEdgeGlow: Adds a thin gradient glow along inner edges.
    ///   - allowDragToOpen: Drag outward on the seam to open.
    ///   - openMode: .gap(seam) or .offscreen(edgePadding).
    ///   - stagger: Extra delay for right door (right starts after left by this amount).
    ///   - contentDelay: Delay applied to the content’s overlay/blur animations.
    ///   - content: The revealed content behind the doors.
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
        self.content = content()
    }
    
    @State private var dragProgress: CGFloat = 0 // 0..1 temporary progress from gesture
    
    public var body: some View {
        let W = UIScreen.main.bounds.width
        let H = UIScreen.main.bounds.height
        let half = W / 2
        
        // Derived animation progress 0..1
        let baseProgress: CGFloat = isOpen ? 1 : 0
        let p = clamp(baseProgress + dragProgress, 0, 1)
        
        // Compute how far doors travel when fully open
        let travel: CGFloat = {
            switch openMode {
            case .gap(let spacing):
                return half + spacing/2 // classic seam
            case .offscreen(let edgePadding):
                return W/2 + half + edgePadding // completely past the edge
            }
        }()
        
        let baseAnim = Animation.easeInOut(duration: reduceMotion ? 0 : duration)
        let leftDelay  = reduceMotion ? 0 : delay
        let rightDelay = reduceMotion ? 0 : (delay + stagger)
        
        ZStack {
            // Revealed content – slightly blurred until fully open for flair
            content
                .padding(.vertical, 40)
                .overlay(
                    // Soft vignette that fades as doors open
                    LinearGradient(
                        colors: [Color.black.opacity(0.35*(1-p)), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blur(radius: (1-p) * 2)
                .animation(
                    baseAnim.delay(reduceMotion ? 0 : contentDelay),
                    value: isOpen
                )
            
            let componnets = componnets()
            let start = componnets.start
            let end = componnets.end
            
            // Doors layer
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
        }
        .contentShape(Rectangle())
        .gesture(dragGesture(width: W), including: allowDragToOpen ? .all : .subviews)
        .onChange(of: isOpen) {
            // Reset transient drag when state changes externally
            withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.25)) {
                dragProgress = 0
            }
        }
    }
    
    private func componnets() -> (start: String, end: String) {
        if text.count >= 2 {
            let componnets = text.components(separatedBy: .whitespaces)
            let start = componnets[0].trimLeadingAndTrailingSpacesAndNewlines()
            let end = componnets[1].trimLeadingAndTrailingSpacesAndNewlines()
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
                .padding(left ? .trailing : .leading, 74)
                .padding(.bottom, 2.5)
        }
        .frame(width: width, height: height)
        .cornerRadius(cornerRadius)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    
    /// A neutral material that adapts to Light/Dark without requiring iOS 18 "dark materials".
    private func doorMaterial(left: Bool) -> some ShapeStyle {
        LinearGradient(
            colors: left
            ? [
                Color(.systemGray3).opacity(0.98),
                Color(.systemGray3).opacity(0.95),
                Color(.systemGray3).opacity(0.92)
            ]
            : [
                Color(.systemGray3).opacity(0.92),
                Color(.systemGray3).opacity(0.95),
                Color(.systemGray3).opacity(0.98)
            ],
            startPoint: left ? .topLeading : .bottomTrailing,
            endPoint: left ? .bottomTrailing : .topLeading
        )
    }
    
    // MARK: - Gesture
    private func dragGesture(width W: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard allowDragToOpen else { return }
                // Positive when dragging outward from center; map to 0..1
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
                    if !isOpen {
                        isOpen = dragAmount > threshold
                    }
                }
                dragProgress = 0
            }
    }
}

// MARK: - Convenience clamp
private func clamp(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max(x, a), b) }

public extension String {
    /// Returns text from the start up to (but not including) `end` offset.
    func substring(to end: Int) -> String {
        guard end > 0 else { return "" }
        let c = count
        let endClamped = min(end, c)
        let endIdx = index(startIndex, offsetBy: endClamped)
        return String(self[..<endIdx])
    }

    /// Returns text starting at `start` offset to the end.
    func substring(from start: Int) -> String {
        let c = count
        guard start < c else { return "" }
        let startClamped = max(0, start)
        let startIdx = index(startIndex, offsetBy: startClamped)
        return String(self[startIdx...])
    }

    /// Returns text within a half-open int range [lower, upper).
    func substring(_ range: Range<Int>) -> String {
        let c = count
        let lower = max(0, min(range.lowerBound, c))
        let upper = max(0, min(range.upperBound, c))
        guard lower < upper else { return "" }
        let startIdx = index(startIndex, offsetBy: lower)
        let endIdx   = index(startIndex, offsetBy: upper)
        return String(self[startIdx..<endIdx])
    }

    // MARK: - Subscript sugar

    subscript(_ range: Range<Int>) -> String {
        substring(range)
    }

    subscript(_ range: ClosedRange<Int>) -> String {
        let c = count
        guard !isEmpty else { return "" }
        let lower = max(0, min(range.lowerBound, c - 1))
        let upper = max(0, min(range.upperBound, c - 1))
        guard lower <= upper else { return "" }
        let startIdx = index(startIndex, offsetBy: lower)
        let endIdx   = index(startIndex, offsetBy: upper)
        // Closed range includes the upper bound; advance by 1
        let afterEnd = index(after: endIdx)
        return String(self[startIdx..<afterEnd])
    }

    subscript(_ range: PartialRangeFrom<Int>) -> String {
        substring(from: range.lowerBound)
    }

    subscript(_ range: PartialRangeUpTo<Int>) -> String {
        substring(to: range.upperBound)
    }

    subscript(_ range: PartialRangeThrough<Int>) -> String {
        // inclusive upper bound
        let c = count
        guard c > 0 else { return "" }
        let upper = min(max(range.upperBound, 0), c - 1) // clamp to [0, c-1]
        return self[0...upper] // uses the ClosedRange<Int> subscript you defined
    }
}

public extension String {
    // Space + CR + LF only (no tabs)
    private static let spaceNewlineSet: CharacterSet = {
        var s = CharacterSet()
        s.insert(charactersIn: " \n\r")
        return s
    }()

    /// Trim at both ends
    func trimmingSpacesAndNewlines() -> String {
        trimmingCharacters(in: Self.spaceNewlineSet)
    }

    /// Trim only the start (leading)
    func trimmingLeadingSpacesAndNewlines() -> String {
        guard let start = rangeOfCharacter(from: Self.spaceNewlineSet.inverted)?.lowerBound
        else { return "" } // string is all spaces/newlines
        return String(self[start...])
    }

    /// Trim only the end (trailing)
    func trimmingTrailingSpacesAndNewlines() -> String {
        guard let end = rangeOfCharacter(from: Self.spaceNewlineSet.inverted,
                                         options: .backwards)?.upperBound
        else { return "" }
        return String(self[..<end])
    }
    
    func trimLeadingAndTrailingSpacesAndNewlines() -> String {
        let text = trimmingLeadingSpacesAndNewlines().trimmingTrailingSpacesAndNewlines()
        return text
    }

    // Optional mutating versions
    mutating func trimSpacesAndNewlines()                   { self = trimmingSpacesAndNewlines() }
    mutating func trimLeadingSpacesAndNewlines()            { self = trimmingLeadingSpacesAndNewlines() }
    mutating func trimTrailingSpacesAndNewlines()           { self = trimmingTrailingSpacesAndNewlines() }
    mutating func trimLeadingAndTrailingSpacesAndNewlines() { self = trimLeadingAndTrailingSpacesAndNewlines() }
}

/// Debossed (stamped into surface) text
struct DebossedText: View {
    let text: String
    var font: Font = .system(size: 16, weight: .heavy, design: .rounded)
    var depth: CGFloat = 1.5      // offset of inner bevel
    var blur: CGFloat = 1.5       // softness of bevel

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark  = scheme == .dark ? Color.gold : Color.gold.opacity(0.65)
        let light = scheme == .dark ? Color.gold.opacity(0.85) : Color.gold

        ZStack {
            // base fill slightly dimmed so the bevel reads
            Text(text)
                .font(font)
                .foregroundStyle(.primary.opacity(scheme == .dark ? 0.75 : 0.8))

            // inner shadow (bottom-right) — makes it look pressed in
            Text(text)
                .font(font)
                .foregroundStyle(dark)
                .offset(x: depth, y: depth)
                .blur(radius: blur)
                .mask(Text(text).font(font))
                .blendMode(.multiply)

            // inner highlight (top-left) — bevel highlight
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
