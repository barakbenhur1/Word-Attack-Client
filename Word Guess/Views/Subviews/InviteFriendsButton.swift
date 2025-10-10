//
//  InviteFriendsButton.swift
//  WordZap
//
//  Created by Barak Ben Hur on 30/09/2025.
//

import SwiftUI
import UIKit

// MARK: - Your button (squeeze-pop + border confetti)
struct InviteFriendsButton: View {
    // Configure with your real values
    private let appStoreID = "6751823737"
    private let website    = URL(string: "https://barakbenhur1.github.io/wordzap-support")!
    private let deepScheme = "wordzap"
    private let refUserID: String
    private let onClick: ((InviteItemSource) -> Void)?
    
    // animation + confetti
    @State private var scale: CGFloat = 1.0
    @State private var burst = false
    
    init(refUserID: String, onClick: ((InviteItemSource) -> Void)? = nil) {
        self.refUserID = refUserID
        self.onClick = onClick
    }
    
    var body: some View {
        Button {
            // Squeeze → pop → confetti → settle
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.16, dampingFraction: 0.8)) { scale = 0.94 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) { scale = 1.08 }
                // fire confetti right at the peak
                burst = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { scale = 1.00 }
                }
            }
            
            // share payload (unchanged)
            let links = ShareLinks(
                appStoreID: appStoreID,
                websiteFallback: website,
                deepScheme: deepScheme,
                ref: refUserID,
                campaign: "virality",
                source: "share_button",
                medium: "app",
                inviteCopy: "I’m playing WordZap — come beat my score!".localized
            )
            let icon = UIImage(named: "AppIcon")
            let subject = "Join me on WordZap".localized
            let itemSource = InviteItemSource(
                text: links.compositeText,
                urls: [links.appStoreURL, links.deepLinkURL],
                image: icon,
                subject: subject
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                onClick?(itemSource)
            }
        } label: {
            Label("Share with friends", systemImage: "square.and.arrow.up")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundStyle(ElevatedButtonStyle.Palette.share.gradient)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThickMaterial)
                        .opacity(0.2)
                )
        }
        .scaleEffect(scale)
        // emits along the button’s border each tap
        .borderBurst($burst, cornerRadius: 12)
    }
}

//
// MARK: - Border Confetti (rectangle outline, fires every time)
//

private struct BorderBurst: UIViewRepresentable {
    @Binding var fire: Bool
    var duration: TimeInterval = 0.18
    var lifetime: TimeInterval = 1.4
    var cornerRadius: CGFloat = 12
    var colors: [UIColor] = [.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
    
    func makeUIView(context: Context) -> Host { Host(cornerRadius: cornerRadius, colors: colors) }
    func updateUIView(_ view: Host, context: Context) {
        Task {
            await MainActor.run {
                if fire {
                    fire = false
                    view.shoot(duration: duration, lifetime: lifetime)
                }
            }
        }
    }
    
    final class Host: UIView {
        let cornerRadius: CGFloat
        let colors: [UIColor]
        init(cornerRadius: CGFloat, colors: [UIColor]) {
            self.cornerRadius = cornerRadius
            self.colors = colors
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            clipsToBounds = false                // ← allow drawing outside
            layer.masksToBounds = false
        }
        required init?(coder: NSCoder) { fatalError() }
        
        func shoot(duration: TimeInterval, lifetime: TimeInterval) {
            layoutIfNeeded()
            guard bounds.width > 0, bounds.height > 0 else {
                DispatchQueue.main.async { [weak self] in self?.shoot(duration: duration, lifetime: lifetime) }
                return
            }
            
            // Expand layer frame a bit so particles aren’t culled at edges
            let pad: CGFloat = 18
            let bigFrame = bounds.insetBy(dx: -pad, dy: -pad)
            
            let emitter = CAEmitterLayer()
            emitter.frame = bounds
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            emitter.renderMode = .unordered
            emitter.birthRate = 1
            emitter.masksToBounds = false        // ← no clipping
            
            // Emit from the button outline
            emitter.emitterShape = .sphere
            emitter.emitterMode  = .outline
            emitter.emitterSize  = bigFrame.size
            
            emitter.emitterCells = makeCells(lifetime: Float(lifetime))
            layer.addSublayer(emitter)
            
            // Emit briefly, then stop & clean up
            emitter.beginTime = CACurrentMediaTime()
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { emitter.birthRate = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + lifetime + 0.25) {
                emitter.removeFromSuperlayer()
            }
        }
        
        private func makeCells(lifetime: Float) -> [CAEmitterCell] {
            colors.flatMap { c in [particle(color: c, rect: true, lifetime: lifetime),
                                   particle(color: c, rect: false, lifetime: lifetime)] }
        }
        
        private func particle(color: UIColor, rect: Bool, lifetime: Float) -> CAEmitterCell {
            let p = CAEmitterCell()
            p.contents = particleImage(color: color, rect: rect).cgImage
            p.birthRate = 180
            p.lifetime  = lifetime
            p.velocity = 280
            p.velocityRange = 140
            p.yAcceleration = 160
            
            // From border outward-ish. We can’t set a per-point normal, so use a wide cone:
            p.emissionLongitude = 0
            p.emissionRange     = .pi * 2        // spread both in/out
            // Bias outward by pushing a bit: increase velocity + gravity so outward feels dominant.
            
            p.scale = 0.9
            p.scaleRange = 0.5
            p.spin = rect ? 4.0 : 2.0
            p.spinRange = rect ? 5.0 : 2.0
            p.alphaSpeed = -0.9 / lifetime
            return p
        }
        
        private func particleImage(color: UIColor, rect: Bool) -> UIImage {
            let s: CGFloat = 10
            return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { _ in
                color.setFill()
                if rect {
                    UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s*0.7),
                                 cornerRadius: s*0.15).fill()
                } else {
                    UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: s, height: s)).fill()
                }
            }
        }
    }
}


// Sweet SwiftUI sugar
private extension View {
    func borderBurst(_ fire: Binding<Bool>,
                     duration: TimeInterval = 0.18,
                     lifetime: TimeInterval = 1.4,
                     cornerRadius: CGFloat = 12,
                     colors: [Color] = [.pink, .orange, .yellow, .green, .blue, .purple]) -> some View {
        overlay(
            BorderBurst(fire: fire,
                        duration: duration,
                        lifetime: lifetime,
                        cornerRadius: cornerRadius,
                        colors: colors.map { UIColor($0) })
            .allowsHitTesting(false)
        )
    }
}
