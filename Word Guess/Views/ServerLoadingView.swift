import SwiftUI
import UIKit

// MARK: - Public API

public struct ServerLoadingView: View {
    public var title: String = "Working on it…"
    public var progress: Double? = nil
    public var showsCancel: Bool = false
    public var onCancel: (() -> Void)? = nil
    
    public var ringSize: CGFloat = 180
    public var ringThickness: CGFloat = 16
    public var isActive: Bool = true
    
    @State private var startDate: Date  = .distantPast
    @State private var opacity: CGFloat = 0
    
    public init(
        title: String = "Working on it…",
        progress: Double? = nil,
        showsCancel: Bool = false,
        onCancel: (() -> Void)? = nil,
        ringSize: CGFloat = 180,
        ringThickness: CGFloat = 16,
        isActive: Bool = true
    ) {
        self.title = title
        self.progress = progress
        self.showsCancel = showsCancel
        self.onCancel = onCancel
        self.ringSize = ringSize
        self.ringThickness = ringThickness
        self.isActive = isActive
    }
    
    public var body: some View {
        let textWidth            = ringSize * 0.92
        let titleHeight          = UIFont.preferredFont(forTextStyle: .headline).lineHeight + 2
        let baseContentHeight    = (ringSize + 32) + 18 + titleHeight + 8
        let cancelBlock: CGFloat = showsCancel ? (44 + 8) : 0
        
        VStack(spacing: 18) {
            ZStack {
                SunkenTrackAligned(size: ringSize, thickness: ringThickness)
                
                if let p = progress {
                    DeterminateRingAligned(progress: CGFloat(max(0, min(1, p))),
                                           thickness: ringThickness)
                    .frame(width: ringSize, height: ringSize)
                } else {
                    IndeterminateRingAligned(thickness: ringThickness, start: startDate)
                        .frame(width: ringSize, height: ringSize)
                }
            }
            .frame(width: ringSize + 2, height: ringSize + 2)
            .drawingGroup(opaque: false, colorMode: .linear)
            .accessibilityHidden(true)
            
            Text(title.localized)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(LoadPalette.title)
                .multilineTextAlignment(.center)
                .frame(width: textWidth, height: titleHeight)
            
            if showsCancel {
                Button("Cancel") { onCancel?() }
                    .buttonStyle(.bordered)
                    .tint(LoadPalette.buttonTint)
            }
        }
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
            startDate = Date()
            withAnimation(.easeInOut(duration: 0.2)) { opacity = 1 }
        }
        .opacity(opacity)
    }
}

// MARK: - Shared stroke style + path

fileprivate struct RingPath: InsettableShape {
    var insetAmount: CGFloat = 0
    func inset(by amount: CGFloat) -> RingPath {
        var c = self
        c.insetAmount += amount
        return c
    }
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: center,
                 radius: r - insetAmount,
                 startAngle: .degrees(0),
                 endAngle: .degrees(360),
                 clockwise: false)
        return p
    }
}

fileprivate func style(_ thickness: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
}

// MARK: - Sunken Track (aligned exactly with rings, with outer/inner rims)

fileprivate struct SunkenTrackAligned: View {
    let size: CGFloat
    let thickness: CGFloat
    
    var body: some View {
        let inset = thickness / 2
        
        ZStack {
            // Base concave band
            RingPath().inset(by: inset)
                .stroke(LoadPalette.trackConcaveFill, style: style(thickness))
            
            // Inner top shadow (pushes the band inward at the top)
            RingPath().inset(by: inset + 0.5)
                .stroke(
                    LinearGradient(
                        colors: [Color.black.opacity(0.18), .clear],
                        startPoint: .top, endPoint: .center
                    ),
                    style: style(thickness - 1)
                )
            
            // Inner bottom highlight (pulls the band forward at the bottom)
            RingPath().inset(by: inset + 0.5)
                .stroke(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.45)],
                        startPoint: .center, endPoint: .bottom
                    ),
                    style: style(thickness - 1)
                )
            
            // ===== Engraved border (rims) =====
            // Outer rim (just outside the band)
            RingPath().inset(by: inset - (thickness / 2) + 0.5)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.10),   // top: slight shadow
                            Color.white.opacity(0.35)    // bottom: lift
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
                )
            
            // Inner rim (just inside the band)
            RingPath().inset(by: inset + (thickness / 2) - 0.5)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.40),   // top: inner catchlight
                            Color.black.opacity(0.08)    // bottom: recess
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
                )
        }
        .frame(width: size, height: size)
        .blendMode(.normal)
        .allowsHitTesting(false)
    }
}

// MARK: - Rings (aligned by using the same inset path)

fileprivate struct IndeterminateRingAligned: View {
    var thickness: CGFloat
    var start: Date  // kept for API compatibility, not used now

    // spinner params
    private let arcLength: CGFloat = 0.22   // 0…1 of circle
    private let revsPerSecond: Double = 0.88

    @State private var spin = false

    var body: some View {
        let inset = thickness / 2
        let duration = 1.0 / revsPerSecond

        // Draw a fixed arc at top (0…arcLength), then rotate the whole thing
        RingPath().inset(by: inset)
            .trim(from: 0, to: arcLength)
            .stroke(LoadPalette.ringGradient, style: style(thickness))
            .rotationEffect(.degrees(spin ? 360 : 0))     // Core Animation handles this
            .rotationEffect(.degrees(-90))               // start at 12 o'clock
            .onAppear {
                // Kick off a CA-backed infinite rotation
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    spin = true
                }
            }
            // No TimelineView, no per-frame state updates → stays smooth under load
    }
}

fileprivate struct DeterminateRingAligned: View {
    var progress: CGFloat
    var thickness: CGFloat
    
    var body: some View {
        let inset = thickness / 2
        RingPath().inset(by: inset)
            .trim(from: 0, to: max(0.001, progress))
            .stroke(LoadPalette.ringGradient, style: style(thickness))
            .rotationEffect(.degrees(-90))
            .animation(.interpolatingSpring(stiffness: 160, damping: 22), value: progress)
    }
}

// MARK: - Palette

fileprivate enum LoadPalette {
    // Card
    static var cardBackground: some ShapeStyle { .thinMaterial }
    static var cardStroke: Color { Color.black.opacity(0.06) }
    static var cardShadow: Color { Color.black.opacity(0.20) }
    
    // Progress
    static var ringGradient: AngularGradient {
        AngularGradient(gradient: Gradient(colors: [
            Color(hue: 0.16, saturation: 0.72, brightness: 1.0).opacity(0.95),
            Color(hue: 0.33, saturation: 0.60, brightness: 0.98).opacity(0.95),
            Color(hue: 0.42, saturation: 0.58, brightness: 0.96).opacity(0.95),
            Color(hue: 0.16, saturation: 0.72, brightness: 1.0).opacity(0.95)
        ]), center: .center)
    }
    
    // Track (fixed sRGB so it never tints with environment)
    static var trackConcaveFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(.sRGB, red: 0.91, green: 0.93, blue: 0.96, opacity: 1), // top
                Color(.sRGB, red: 0.97, green: 0.98, blue: 1.00, opacity: 1)  // bottom
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
    
    // Text / button
    static var title: Color { Color.black.opacity(0.92) }
    static var buttonTint: Color { Color(hue: 0.58, saturation: 0.65, brightness: 0.85) }
}
