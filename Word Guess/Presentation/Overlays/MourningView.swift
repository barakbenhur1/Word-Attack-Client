//
//  MourningView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 15/08/2025.
//  🖤 Subtle "loss" effect: rainy particles + vignette overlay (UIKit + SwiftUI)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Style

public struct MourningStyle {
    public var colors: [UIColor]          // raindrop tint(s)
    public var baseBirthRate: Float       // per-cell baseline (scaled by intensity)
    public var lifetime: Float
    public var velocity: (min: CGFloat, max: CGFloat)
    public var yAcceleration: CGFloat
    public var emissionSpread: CGFloat    // angular spread around downward vector
    public var dropSize: CGSize
    public var blurTrail: Bool            // tiny blur for a streak feel
    
    public init(colors: [UIColor] = [UIColor(white: 1, alpha: 0.9)],
                baseBirthRate: Float = 150,
                lifetime: Float = 3.8,
                velocity: (CGFloat, CGFloat) = (240, 380),
                yAcceleration: CGFloat = 260,
                emissionSpread: CGFloat = .pi/20,
                dropSize: CGSize = CGSize(width: 2.0, height: 10.0),
                blurTrail: Bool = true) {
        self.colors = colors
        self.baseBirthRate = baseBirthRate
        self.lifetime = lifetime
        self.velocity = velocity
        self.yAcceleration = yAcceleration
        self.emissionSpread = emissionSpread
        self.dropSize = dropSize
        self.blurTrail = blurTrail
    }
    
    public static let standard = MourningStyle()
    public static let heavy = MourningStyle(baseBirthRate: 220,
                                            lifetime: 4.2,
                                            velocity: (280, 460),
                                            yAcceleration: 320,
                                            emissionSpread: .pi/28,
                                            dropSize: CGSize(width: 2.2, height: 14))
    public static let blue = MourningStyle(colors: [UIColor.systemTeal.withAlphaComponent(0.95),
                                                    UIColor.systemBlue.withAlphaComponent(0.9)])
}

// MARK: - UIKit emitter

public final class GriefEmitterView: UIView {
    private var emitter: CAEmitterLayer?
    private static var cache: [UInt32: CGImage] = [:]   // color→CGImage
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
    }
    
    public func start(style: MourningStyle = .standard,
                      duration: TimeInterval = 2.0,
                      intensity: Float = 1.0,
                      onDone: @escaping () -> Void)
    {
        stop()
        
        // Accessibility: gentle dim flash only
        if UIAccessibility.isReduceMotionEnabled {
            reduceMotionFallback(duration: duration, onDone: onDone)
            return
        }
        
        let layer = CAEmitterLayer()
        layer.emitterShape = .line
        layer.emitterMode  = .outline
        layer.emitterPosition = CGPoint(x: bounds.midX, y: -2)
        layer.emitterSize     = CGSize(width: bounds.width, height: 1)
        layer.beginTime       = CACurrentMediaTime()
        layer.renderMode      = .oldestFirst
        
        var cells: [CAEmitterCell] = []
        for color in (style.colors.isEmpty ? [UIColor.white] : style.colors) {
            let c = CAEmitterCell()
            c.contents       = GriefEmitterView.dropImage(for: color, size: style.dropSize, blur: style.blurTrail)
            c.birthRate      = max(0, style.baseBirthRate * intensity)
            c.lifetime       = style.lifetime
            c.lifetimeRange  = style.lifetime * 0.25
            let baseV = (style.velocity.min + style.velocity.max) * 0.5
            c.velocity       = baseV
            c.velocityRange  = (style.velocity.max - style.velocity.min) * 0.5
            c.emissionLongitude = .pi                       // downward
            c.emissionRange     = style.emissionSpread
            c.scale          = 1.0
            c.alphaSpeed     = -1.0 / (style.lifetime * 1.4)
            c.yAcceleration  = style.yAcceleration
            cells.append(c)
        }
        
        layer.emitterCells = cells
        self.layer.addSublayer(layer)
        self.emitter = layer
        
        // Haptics (error “thud”)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.stop()
            onDone()
        }
    }
    
    public func stop() {
        emitter?.birthRate = 0
        emitter?.removeFromSuperlayer()
        emitter = nil
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let e = emitter else { return }
        e.emitterPosition = CGPoint(x: bounds.midX, y: -2)
        e.emitterSize     = CGSize(width: bounds.width, height: 1)
    }
    
    // MARK: drawing
    
    private static func dropImage(for color: UIColor, size: CGSize, blur: Bool) -> CGImage {
        let key = color.argb32 ^ UInt32(size.width * 10) ^ (UInt32(size.height * 10) << 8) ^ (blur ? 0x1 : 0x0)
        if let cg = cache[key] { return cg }
        
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                                    cornerRadius: size.width * 0.5)
            let col = color
            if blur {
                // draw soft core + faint trail
                col.setFill(); path.fill()
                col.withAlphaComponent(0.35).setFill()
                UIBezierPath(roundedRect: CGRect(x: size.width*0.15, y: -size.height*0.25,
                                                 width: size.width*0.7, height: size.height*1.4),
                             cornerRadius: size.width*0.35).fill()
            } else {
                col.setFill(); path.fill()
            }
        }
        let cg = img.cgImage!
        cache[key] = cg
        return cg
    }
    
    private func reduceMotionFallback(duration: TimeInterval, onDone: @escaping () -> Void) {
        // Fade-in/out dark veil
        let veil = UIView(frame: bounds)
        veil.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        veil.alpha = 0
        addSubview(veil)
        veil.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            veil.leadingAnchor.constraint(equalTo: leadingAnchor),
            veil.trailingAnchor.constraint(equalTo: trailingAnchor),
            veil.topAnchor.constraint(equalTo: topAnchor),
            veil.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        UIView.animate(withDuration: 0.12, animations: { veil.alpha = 1 }) { _ in
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
                veil.alpha = 0
            } completion: { _ in
                veil.removeFromSuperview()
                onDone()
            }
        }
    }
}

// MARK: - SwiftUI bridge

private struct MourningOverlay: UIViewRepresentable {
    @Binding var isActive: Bool
    let style: MourningStyle
    let duration: TimeInterval
    let intensity: Float
    let vignetteOpacity: Double
    
    final class Coordinator { var isRunning = false }
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeUIView(context: Context) -> GriefEmitterView { GriefEmitterView() }
    
    func updateUIView(_ uiView: GriefEmitterView, context: Context) {
        if isActive && !context.coordinator.isRunning {
            context.coordinator.isRunning = true
            uiView.start(style: style, duration: duration, intensity: intensity) {
                DispatchQueue.main.async {
                    context.coordinator.isRunning = false
                    self.isActive = false
                }
            }
        }
        if !isActive && context.coordinator.isRunning {
            context.coordinator.isRunning = false
            uiView.stop()
        }
    }
}

// MARK: - Public SwiftUI modifier

public extension View {
    /// Show a subtle rainy "loss" overlay.
    ///
    /// Usage:
    /// ```swift
    /// @State private var lost = false
    /// ...
    /// .mourn($lost, style: .blue, duration: 2.4, intensity: 1.0, vignetteOpacity: 0.35)
    /// ```
    func mourn(_ isActive: Binding<Bool>,
               style: MourningStyle = .heavy,
               duration: TimeInterval = 4,
               intensity: Float = 1.0,
               vignetteOpacity: Double = 0.32) -> some View {
        ZStack {
            // Soft vignette/dimming when active
            if isActive.wrappedValue {
                LinearGradient(colors: [.black.opacity(vignetteOpacity * 0.7),
                                        .black.opacity(vignetteOpacity)],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .transition(.opacity)
                .allowsHitTesting(false)
            }
            self
            if isActive.wrappedValue {
                MourningOverlay(isActive: isActive,
                                style: style,
                                duration: duration,
                                intensity: intensity,
                                vignetteOpacity: vignetteOpacity)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Helpers

#if canImport(UIKit)
private extension UIColor {
    var argb32: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let A = UInt32(a * 255 + 0.5)
        let R = UInt32(r * 255 + 0.5)
        let G = UInt32(g * 255 + 0.5)
        let B = UInt32(b * 255 + 0.5)
        return (A << 24) | (R << 16) | (G << 8) | B
    }
}
#endif
