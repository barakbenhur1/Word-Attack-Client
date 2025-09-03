import SwiftUI
import UIKit

public enum Language: String { case en, he }

public struct Tooltip<Content: View>: View {
    public enum Trigger { case longPress(duration: Double = 0.35), tap, manual }
    
    // Config
    private let text: String
    private let language: Language
    private let trigger: Trigger
    private let showDelay: Double
    private let autoDismissAfter: Double?
    private let arrowSize: CGSize
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let background: AnyShapeStyle
    private let foreground: Color
    private let shadowRadius: CGFloat
    private let contentGap: CGFloat
    private let userMaxWidth: CGFloat?
    private let dismissOnTapOutside: Bool
    private let minBubbleWidth: CGFloat = 92
    
    // Host content
    private let content: () -> Content
    private let externalIsPresented: Binding<Bool>?
    
    // State
    @State private var isPresentedLocal = false
    @State private var hostSize: CGSize = .zero
    @State private var hostFrame: CGRect = .zero
    @State private var measuredBubbleOuter: CGSize = .zero
    
    // appear/disappear driver
    @State private var pop: Bool = false
    
    // Screen width snapshot
    private let screenWidth: CGFloat = {
#if os(iOS) || os(tvOS)
        UIScreen.main.bounds.width
#elseif os(macOS)
        NSScreen.main?.visibleFrame.width ?? 1024
#else
        1024
#endif
    }()
    
    // Init
    public init(
        _ text: String,
        language: Language,
        trigger: Trigger = .manual,
        showDelay: Double = 0.0,
        autoDismissAfter: Double? = nil,
        arrowSize: CGSize = .init(width: 12, height: 8),
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 10,
        background: some ShapeStyle = .ultraThinMaterial,
        foreground: Color = .primary,
        shadowRadius: CGFloat = 6,
        contentGap: CGFloat = 10,
        maxWidth: CGFloat? = 420,
        dismissOnTapOutside: Bool = true,
        isPresented: Binding<Bool>? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.text = text
        self.language = language
        self.trigger = trigger
        self.showDelay = showDelay
        self.autoDismissAfter = autoDismissAfter
        self.arrowSize = arrowSize
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.background = AnyShapeStyle(background)
        self.foreground = foreground
        self.shadowRadius = shadowRadius
        self.contentGap = contentGap
        self.userMaxWidth = maxWidth
        self.dismissOnTapOutside = dismissOnTapOutside
        self.externalIsPresented = isPresented
        self.content = content
    }
    
    private var isPresented: Bool { externalIsPresented?.wrappedValue ?? isPresentedLocal }
    private func setPresented(_ v: Bool) { if let b = externalIsPresented { b.wrappedValue = v } else { isPresentedLocal = v } }
    
    public var body: some View {
        HostSizeReader(size: $hostSize) {                          // ✅ single writer for host size
            content()
                .background(GlobalFrameReader(frame: $hostFrame))   // ✅ debounced global frame
                .overlay(alignment: .center) {
                    if isPresented {
                        let isEN = (language == .en)
                        tooltipRow
                            .fixedSize()
                            .offset(x: horizontalOffsetUsingClampedWidth(), y: 0)
                        // appear/disappear
                            .scaleEffect(pop ? 1.0 : 0.85, anchor: isEN ? .leading : .trailing)
                            .opacity(pop ? 1.0 : 0.0)
                            .onAppear { withAnimation(showSpring) { pop = true } }
                            .onDisappear { withAnimation(hideSpring) { pop = false } }
                        // size-reactive, but not preference-driven
                            .animation(sizeSpring, value: measuredBubbleOuter)
                            .animation(sizeSpring, value: hostSize)
                            .zIndex(10)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if case .tap = trigger { isPresented ? hide() : show() } }
                .onLongPressGesture(minimumDuration: { if case let .longPress(d) = trigger { return d } else { return 9999 } }()) {
                    if case .longPress = trigger { isPresented ? hide() : show() }
                }
                .background(
                    Group {
                        if dismissOnTapOutside && isPresented {
                            Color.black.opacity(0.001)
                                .ignoresSafeArea()
                                .onTapGesture { hide() }
                        }
                    }
                )
        }
        // keep pop synced for external binding changes
        .onChange(of: isPresented) { _, now in withAnimation(now ? showSpring : hideSpring) { pop = now } }
    }
    
    // MARK: - Pieces
    
    private var tooltipRow: some View {
        let isEN = (language == .en)
        return bubbleWithArrow(isEN)
    }
    
    private func bubbleWithArrow(_ isEN: Bool) -> some View {
        HStack {
            if isEN {
                Arrow(direction: .left)
                    .fill(.regularMaterial)
                    .frame(width: arrowSize.width, height: arrowSize.height)
                    .shadow(radius: shadowRadius * 0.6, y: 0.5)
                
                bubble
                    .offset(x:  -arrowSize.width)
            } else {
                bubble
                    .offset(x: contentGap + 1.5)
                    .zIndex(2)
                
                Arrow(direction: .right)
                    .fill(.regularMaterial)
                    .offset(x: -contentGap)
                    .frame(width: arrowSize.width, height: arrowSize.height)
                    .shadow(radius: shadowRadius * 0.6, y: 0.5)
            }
        }
    }
    
    private var bubble: some View {
        let outerMax = effectiveMaxBubbleOuterWidth()
        let innerMaxRaw = max(0, outerMax - (padding * 2))
        let safeInnerMax = max(innerMaxRaw, 1)
        let innerMin = min(max(0, minBubbleWidth - padding * 2), safeInnerMax)
        
        // Shrink text if bubble taller than host by > 10
        let shouldShrink = measuredBubbleOuter.height > hostSize.height - 10
        let font: Font = shouldShrink ? .caption2 : .caption
        
        return BubbleSizeReader(size: $measuredBubbleOuter) {       // ✅ single writer for bubble size
            Text(text)
                .font(font)
                .foregroundColor(foreground)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: innerMin, maxWidth: safeInnerMax, alignment: .center)
                .padding(.horizontal, padding)
                .padding(.vertical, padding - 5)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(background)
                )
                .shadow(radius: shadowRadius, y: 1)
                .animation(sizeSpring, value: shouldShrink)
        }
        .frame(minWidth: minBubbleWidth)
    }
    
    // MARK: - Positioning & clamping
    
    private func effectiveMaxBubbleOuterWidth() -> CGFloat {
        let margin: CGFloat = 8
        if language == .en {
            let startX = hostFrame.maxX + contentGap + arrowSize.width
            let available = max(0, (screenWidth - margin) - startX)
            return min(userMaxWidth ?? .infinity, available)
        } else {
            let endX = hostFrame.minX - contentGap - arrowSize.width
            let available = max(0, endX - margin)
            return min(userMaxWidth ?? .infinity, available)
        }
    }
    
    private func horizontalOffsetUsingClampedWidth() -> CGFloat {
        // host half-width
        let halfHost = hostSize.width / 2
        // bubble half-width (fallback to min width until measured)
        let halfBubble = max(measuredBubbleOuter.width, minBubbleWidth) / 2
        // gap + arrow so the arrow has room between host and bubble
        let delta = halfHost + contentGap + arrowSize.width + halfBubble + 5

        return (language == .en) ? delta : -delta
    }
    
    private func show() {
        let present = { withAnimation(showSpring) { self.setPresented(true) } }
        if showDelay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: present) }
        else { present() }
        if let t = autoDismissAfter, t > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { hide() }
        }
    }
    
    private func hide() {
        withAnimation(hideSpring) { setPresented(false) }
    }
    
    // MARK: - Springs
    private var showSpring: Animation { .spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.05) }
    private var hideSpring: Animation { .spring(response: 0.26, dampingFraction: 0.95, blendDuration: 0.05) }
    private var sizeSpring: Animation { .spring(response: 0.28, dampingFraction: 0.9) }
}

// MARK: - Arrow
private struct Arrow: Shape {
    enum Direction { case left, right }
    let direction: Direction
    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch direction {
        case .left:
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        case .right:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Debounced global frame reader (no per-frame spam)
private struct GlobalFrameReader: View {
    @Binding var frame: CGRect
    @State private var last: CGRect = .zero
    var threshold: CGFloat = 0.5
    
    var body: some View {
        GeometryReader { proxy in
            let f = proxy.frame(in: .global)
            Color.clear
                .onAppear { frame = f; last = f }
                .onChange(of: f) { _, new in
                    guard abs(new.origin.x - last.origin.x) > threshold ||
                            abs(new.origin.y - last.origin.y) > threshold ||
                            abs(new.size.width - last.size.width) > threshold ||
                            abs(new.size.height - last.size.height) > threshold
                    else { return }
                    last = new
                    frame = new
                }
        }
        .transaction { $0.animation = nil }
    }
}

// MARK: - Distinct preference keys + readers

private struct HostSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct BubbleSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct HostSizeReader<C: View>: View {
    @Binding var size: CGSize
    @State private var last: CGSize = .zero
    var threshold: CGFloat = 0.5
    let content: () -> C
    
    var body: some View {
        content()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HostSizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(HostSizeKey.self) { new in
                guard abs(new.width - last.width) > threshold ||
                        abs(new.height - last.height) > threshold else { return }
                last = new
                size = new
            }
            .transaction { $0.animation = nil }
    }
}

private struct BubbleSizeReader<C: View>: View {
    @Binding var size: CGSize
    @State private var last: CGSize = .zero
    var threshold: CGFloat = 0.5
    let content: () -> C
    
    var body: some View {
        content()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: BubbleSizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(BubbleSizeKey.self) { new in
                guard abs(new.width - last.width) > threshold ||
                        abs(new.height - last.height) > threshold else { return }
                last = new
                size = new
            }
            .transaction { $0.animation = nil }
    }
}

// MARK: - View sugar

public extension View {
    func tooltip(
        _ text: String,
        language: Language,
        trigger: Tooltip<Self>.Trigger = .manual,
        showDelay: Double = 0.0,
        autoDismissAfter: Double? = nil,
        contentGap: CGFloat = 5,
        maxWidth: CGFloat? = 320,
        arrowSize: CGSize = .init(width: 12, height: 8),
        isPresented: Binding<Bool>? = nil
    ) -> some View {
        Tooltip(
            text,
            language: language,
            trigger: trigger,
            showDelay: showDelay,
            autoDismissAfter: autoDismissAfter,
            arrowSize: arrowSize,
            cornerRadius: 12,
            padding: 10,
            background: .ultraThinMaterial,
            foreground: .primary,
            shadowRadius: 6,
            contentGap: contentGap,
            maxWidth: maxWidth,
            dismissOnTapOutside: true,
            isPresented: isPresented
        ) { self }
    }
}
