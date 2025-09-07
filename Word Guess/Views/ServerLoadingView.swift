import SwiftUI
import UIKit

// MARK: - Public API

public struct ServerLoadingView: View {
    // Copy & data
    public var title: String = "Working on it…"
    public var messages: [String] = ServerLoadingView.defaultServerMessages
    public var progress: Double? = nil                  // nil = indeterminate
    public var showsCancel: Bool = false
    public var onCancel: (() -> Void)? = nil
    
    // Layout & style
    public var ringSize: CGFloat = 260
    public var ringThickness: CGFloat = 16
    public var cycleEvery: TimeInterval = 1.15          // message cadence
    
    // NEW: lets overlay tell us when we’re being dismissed so we can freeze
    public var isActive: Bool = true
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var appearDate: Date = .distantPast
    @State private var frozenIndex: Int? = nil
    @State private var opacity:  CGFloat = 0
    @State private var appeared = false
    
    public init(title: String = "Working on it…",
                messages: [String] = ServerLoadingView.defaultServerMessages,
                progress: Double? = nil,
                showsCancel: Bool = false,
                onCancel: (() -> Void)? = nil,
                ringSize: CGFloat = 140,
                ringThickness: CGFloat = 16,
                cycleEvery: TimeInterval = 0.1,
                isActive: Bool = true) {
        self.title = title
        self.messages = messages
        self.progress = progress
        self.showsCancel = showsCancel
        self.onCancel = onCancel
        self.ringSize = ringSize
        self.ringThickness = ringThickness
        self.cycleEvery = max(0.6, cycleEvery)
        self.isActive = isActive
    }
    
    public var body: some View {
        // ---- Fixed metrics to prevent vertical movement ----
        let textWidth     = ringSize * 0.92
        let titleHeight   = uiLineHeight(.headline) + 2          // single-line title
//        let messageHeight = uiLineHeight(.subheadline) * 2 + 4  // reserve up to 2 lines
        
        // Precompute the content height (ring + spacing + text + optional cancel)
        let baseContentHeight = (ringSize + 32)    // ring stack fixed frame
        + 18                  // spacing
        + titleHeight
        + 8
//        + messageHeight
        let cancelBlock: CGFloat = showsCancel ? (44 + 8) : 0    // approx button + spacing
        
        VStack(spacing: 18) {
            // ---------- RING STACK (fixed size) ----------
            ZStack {
                NetworkPulses(size: ringSize * 0.86)
                    .accessibilityHidden(true)
                
                Circle()
                    .stroke(LoadPalette.track,
                            style: StrokeStyle(lineWidth: ringThickness, lineCap: .round))
                
                if let p = progress {
                    DeterminateRing(progress: CGFloat(max(0.0, min(1.0, p))),
                                    thickness: ringThickness)
                    .accessibilityLabel("Progress")
                    .accessibilityValue("\(Int(p * 100)) percent")
                } else {
                    IndeterminateRing(thickness: ringThickness)
                        .accessibilityLabel("Loading")
                }
                
                // Center logo chip (swap to your logo if you like)
                Circle()
                    .fill(LoadPalette.track)
                    .frame(width: ringSize * 0.38, height: ringSize * 0.38)
                    .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 8)
                    .accessibilityHidden(true)
            }
            .frame(width: ringSize + 32, height: ringSize + 32) // <- fixed ring stack
            
            // ---------- TITLE + STATUS (fixed width & height) ----------
//            TimelineView(.animation) { context in
//                let t = context.date.timeIntervalSince(appearDate)
//                let count = messages.count
                
                // Compute live index
//                let liveIdx = count > 0 ? max(0, Int(floor(t / cycleEvery))) % count : 0
                
                // Display index freezes during dismiss
//                let displayIdx = frozenIndex ?? liveIdx
//                let current = (count > 0) ? messages[displayIdx] : ""
                
                VStack(spacing: 8) {
                    // Title: fixed height
                    Text(title.localized)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundStyle(LoadPalette.title)
                        .multilineTextAlignment(.center)
                        .frame(width: textWidth, height: titleHeight, alignment: .center)
                        .accessibilityAddTraits(.isHeader)
                    
                    // Status text: lock to 2-line height, crossfade only when active
//                    ZStack {
//                        Text(current)
//                            .id(displayIdx) // drives crossfade
//                            .font(.system(.subheadline, design: .rounded))
//                            .foregroundStyle(LoadPalette.subtitle)
//                            .multilineTextAlignment(.center)
//                            .lineLimit(2)
//                            .minimumScaleFactor(0.9)
//                            .frame(width: textWidth, height: messageHeight, alignment: .center)
//                            .fixedSize(horizontal: false, vertical: true)
//                            .transition(.opacity)
//                    }
//                    .animation(isActive && frozenIndex == nil
//                               ? (reduceMotion ? nil : .easeInOut(duration: 0.35))
//                               : nil,
//                               value: displayIdx)
                }
                .padding(.horizontal, 16)
//            }
            // Don’t animate container layout when the message index changes
            //            .transaction { $0.animation = nil }
            
            if showsCancel {
                Button {
                    guard appeared else { return }
                    onCancel?()
                }
                label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(LoadPalette.buttonTint)
                .accessibilityLabel("Cancel")
            }
        }
        // Reserve constant overall height so nothing nudges at the very end
        .frame(minHeight: baseContentHeight + cancelBlock)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LoadPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LoadPalette.cardStroke, lineWidth: 1)
                )
                .shadow(color: LoadPalette.cardShadow, radius: 22, x: 0, y: 14)
        )
        .padding(24)
        .onAppear {
            appeared = true
            appearDate = Date()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            
            Task(priority: .utility) {
                try? await Task.sleep(nanoseconds: 100_000_000)
                withAnimation { opacity = 1 }
            }
        }
        .onDisappear { appeared = false }
        .ignoresSafeArea(.keyboard)
        // Freeze the current message index the instant we start dismissing
        .onChange(of: isActive) { _, active in
            if !active, frozenIndex == nil {
                // Compute the live index one last time and pin it
                let t = Date().timeIntervalSince(appearDate)
                let count = messages.count
                let liveIdx = count > 0 ? max(0, Int(floor(t / cycleEvery))) % count : 0
                frozenIndex = liveIdx
            }
        }
        .opacity(opacity)
    }
    
    // UIKit line height for a given text style (respects Dynamic Type)
    private func uiLineHeight(_ style: UIFont.TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: style).lineHeight
    }
}

// MARK: - Default rotating copy

public extension ServerLoadingView {
    static let defaultServerMessages: [String] = [
//        "Connecting to servers…",
//        "Negotiating session…",
//        "Priming caches…",
//        "Streaming first tokens…",
//        "Almost there…"
    ]
}

// MARK: - Pieces

fileprivate struct IndeterminateRing: View {
    var thickness: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let speed = 0.85
            let tail = (t * speed).truncatingRemainder(dividingBy: 1)
            let len  = 0.30 + 0.12 * (sin(t * 1.6) * 0.5 + 0.5)
            let head = (tail + len).truncatingRemainder(dividingBy: 1)
            
            ZStack {
                if head > tail {
                    Circle()
                        .trim(from: tail, to: head)
                        .stroke(LoadPalette.ringGradient,
                                style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else {
                    Circle()
                        .trim(from: tail, to: 1)
                        .stroke(LoadPalette.ringGradient,
                                style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .trim(from: 0, to: head)
                        .stroke(LoadPalette.ringGradient,
                                style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .animation(reduceMotion ? nil : .linear(duration: 1/60), value: t)
        }
        .accessibilityHidden(true)
    }
}

fileprivate struct DeterminateRing: View {
    var progress: CGFloat
    var thickness: CGFloat
    
    var body: some View {
        Circle()
            .trim(from: 0, to: max(0.001, progress))
            .stroke(LoadPalette.ringGradient,
                    style: StrokeStyle(lineWidth: thickness, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.easeInOut(duration: 0.25), value: progress)
            .accessibilityHidden(true)
    }
}

fileprivate struct NetworkPulses: View {
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            if reduceMotion {
                Circle()
                    .stroke(LoadPalette.pulseStroke, lineWidth: 1)
                    .frame(width: size, height: size)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let base = (t * 0.7).truncatingRemainder(dividingBy: 1)
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            let phase   = (base + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                            let scale   = 1 + 0.25 * phase
                            let opacity = (1 - phase) * 0.18
                            Circle()
                                .stroke(LoadPalette.pulseStroke, lineWidth: 1)
                                .frame(width: size, height: size)
                                .scaleEffect(scale)
                                .opacity(opacity)
                        }
                    }
                    .animation(.linear(duration: 1/60), value: t)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Palette / Theme

fileprivate enum LoadPalette {
    // Card
    static var cardBackground: some ShapeStyle { .thinMaterial }
    static var cardStroke: Color { Color.primary.opacity(0.06) }
    static var cardShadow: Color { Color.black.opacity(0.20) }
    
    // Ring
    static var ringGradient: AngularGradient {
        AngularGradient(gradient: Gradient(colors: [
            Color(hue: 0.15, saturation: 0.65, brightness: 1.0).opacity(0.95),
            Color(hue: 0.33, saturation: 0.55, brightness: 0.98).opacity(0.95),
            Color(hue: 0.42, saturation: 0.55, brightness: 0.95).opacity(0.95),
            Color(hue: 0.15, saturation: 0.65, brightness: 1.0).opacity(0.95)
        ]), center: .center)
    }
    static var track: Color { Color.primary.opacity(0.08) }
    
    // Pulses
    static var pulseStroke: Color { Color.primary.opacity(0.10) }
    
    // Center chip
    static var centerFill: some ShapeStyle {
        RadialGradient(colors: [Color(white: 0.98), Color(white: 0.90)],
                       center: .center, startRadius: 2, endRadius: 60)
    }
    static var centerGlyph: Color { Color.primary.opacity(0.75) }
    
    // Copy
    static var title: Color { Color.primary.opacity(0.92) }
    static var subtitle: Color { Color.secondary.opacity(0.86) }
    
    // Button
    static var buttonTint: Color { Color.accentColor.opacity(0.95) }
}

// MARK: - Overlay convenience

public extension View {
    /// Presents a centered ServerLoadingView as an overlay.
    /// Note: we pass `isActive: isPresented` so the view can freeze its message index during dismiss.
    func serverLoadingOverlay(isPresented: Bool,
                              title: String = "Working on it…",
                              messages: [String] = ServerLoadingView.defaultServerMessages,
                              progress: Double? = nil,
                              showsCancel: Bool = false,
                              onCancel: (() -> Void)? = nil) -> some View {
        ZStack {
            self
            if isPresented {
                Color.black.opacity(0.18).ignoresSafeArea()
                    .transition(.opacity)
                    .ignoresSafeArea(.keyboard)
                ServerLoadingView(title: title,
                                  messages: messages,
                                  progress: progress,
                                  showsCancel: showsCancel,
                                  onCancel: onCancel,
                                  isActive: true)
                .transition(.opacity) // <- remove scale to avoid perceptual “hop”
            } else {
                // keep the layout stable even during the first frame of dismissal
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
        // When the overlay toggles false, rebuild with isActive: false for one frame
        .onChange(of: isPresented) { _, shown in
            // No-op here; the ServerLoadingView freezes itself via its isActive flag above.
        }
    }
}
