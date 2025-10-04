//
//  RainbowPartyView.swift
//  WordZap
//
//  🎉 Robust confetti overlay (UIKit emitter + SwiftUI bridge)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - UIKit emitter

public final class RainbowEmitterView: UIView {
    private var emitter: CAEmitterLayer?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    
    public func start(duration: TimeInterval = 2.0,
                      intensity: Float = 0.45,
                      animationDone: @escaping () -> Void)
    {
        stop()
        
        let layer = CAEmitterLayer()
        layer.emitterShape   = .line
        layer.emitterMode    = .outline
        layer.emitterPosition = CGPoint(x: bounds.midX, y: -4)
        layer.emitterSize     = CGSize(width: bounds.width, height: 1)
        layer.beginTime       = CACurrentMediaTime()
        
        let colors: [UIColor] = [
            .systemRed, .systemOrange, .systemYellow,
            .systemGreen, .systemBlue, .systemPurple, .white
        ]
        
        layer.emitterCells = colors.map { color in
            let c = CAEmitterCell()
            c.contents       = RainbowEmitterView.boxImage(color: color).cgImage
            c.birthRate      = 170 * intensity
            c.lifetime       = 3.6
            c.lifetimeRange  = 1.2
            c.velocity       = 240
            c.velocityRange  = 140
            c.emissionLongitude = .pi        // shoot downward
            c.emissionRange     = .pi / 7
            c.spin           = 2
            c.spinRange      = 4
            c.scale          = 0.55
            c.scaleRange     = 0.45
            c.yAcceleration  = 120
            return c
        }
        
        self.layer.addSublayer(layer)
        self.emitter = layer
        
        // Haptics (soft success)
#if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
        
        // Auto-stop
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.stop()
            animationDone()
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
        e.emitterPosition = CGPoint(x: bounds.midX, y: -4)
        e.emitterSize     = CGSize(width: bounds.width, height: 1)
    }
    
    private static func boxImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 8, height: 12)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = UIScreen.main.scale
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2)
            color.setFill(); path.fill()
        }
    }
}

// Quick UIKit helper
public extension UIView {
    func celebrateWin(duration: TimeInterval = 2.0, intensity: Float = 0.45) {
        let confetti = RainbowEmitterView(frame: bounds)
        confetti.translatesAutoresizingMaskIntoConstraints = false
        addSubview(confetti)
        NSLayoutConstraint.activate([
            confetti.leadingAnchor.constraint(equalTo: leadingAnchor),
            confetti.trailingAnchor.constraint(equalTo: trailingAnchor),
            confetti.topAnchor.constraint(equalTo: topAnchor),
            confetti.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        confetti.start(duration: duration, intensity: intensity) {}
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
            confetti.removeFromSuperview()
        }
    }
}

// MARK: - SwiftUI bridge

private struct ConfettiOverlay: UIViewRepresentable {
    @Binding var isActive: Bool
    let duration: TimeInterval
    let intensity: Float
    
    final class Coordinator {
        var isRunning = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeUIView(context: Context) -> RainbowEmitterView {
        RainbowEmitterView()
    }
    
    func updateUIView(_ uiView: RainbowEmitterView, context: Context) {
        // Start exactly once per activation.
        if isActive && !context.coordinator.isRunning {
            context.coordinator.isRunning = true
            uiView.start(duration: duration, intensity: intensity) {
                // Finish on main queue, outside of the update pass.
                DispatchQueue.main.async {
                    context.coordinator.isRunning = false
                    self.isActive = false
                }
            }
        }
        // If turned off early, stop.
        if !isActive && context.coordinator.isRunning {
            context.coordinator.isRunning = false
            uiView.stop()
        }
    }
}

// MARK: - Public modifier

public struct CelebrationStyle: Equatable {
    public static let standard = CelebrationStyle()   // reserved for future options
}
public extension View {
    /// Overlay confetti when `isActive` toggles true. Automatically hides after `duration`.
    func celebrate(_ isActive: Binding<Bool>,
                   style _: CelebrationStyle = .standard,
                   duration: TimeInterval = 4,
                   intensity: Float = 1) -> some View {
        ZStack {
            self
            if isActive.wrappedValue {
                ConfettiOverlay(isActive: isActive,
                                duration: duration,
                                intensity: intensity)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        // No state mutation inside body; no Canvas/GraphicsContext.
    }
}
