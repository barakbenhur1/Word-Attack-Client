//
//  InviteJoinView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 30/09/2025.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct InviteJoinView: View {
    let ref: String
    var onClaim: (String) -> Void = { _ in }

    @Environment(\.layoutDirection) private var dir
    @State private var copied = false
    @State private var press = false
    @State private var t: CGFloat = 0

    var body: some View {
        ZStack {
            // Frosted, semi-clear backdrop: live blur + soft tint
            Color.clear
                .background(.ultraThinMaterial) // iOS 15+: blurs what's underneath
                .overlay(
                    LinearGradient(
                        colors: [
                            Color(hue: 0.40, saturation: 0.78, brightness: 0.82).opacity(0.18),
                            Color.black.opacity(0.25)
                        ],
                        startPoint: dir == .rightToLeft ? .topTrailing : .topLeading,
                        endPoint:   dir == .rightToLeft ? .bottomLeading : .bottomTrailing
                    )
                )
                .ignoresSafeArea()

            // Soft animated glow (subtle over blur)
            RoundedRectangle(cornerRadius: 48)
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(hue: 0.40, saturation: 0.78, brightness: 0.82), // emerald
                            Color(hue: 0.56, saturation: 0.60, brightness: 0.80), // cyan
                            Color(hue: 0.86, saturation: 0.50, brightness: 0.80), // pink
                            Color(hue: 0.40, saturation: 0.78, brightness: 0.82)
                        ]),
                        center: .center, angle: .degrees(Double(t) * 360)
                    )
                )
                .blur(radius: 50)
                .opacity(0.16)
                .frame(width: 420, height: 420)
                .animation(.linear(duration: 8).repeatForever(autoreverses: false), value: t)
                .onAppear { t = 1 }

            // Card
            VStack(spacing: 18) {
                // Icon + title
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
                            .frame(width: 88, height: 88)
                            .shadow(color: .black.opacity(0.4), radius: 16, y: 10)

                        Image(systemName: "gift.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(hue: 0.40, saturation: 0.78, brightness: 0.82),
                                        Color(hue: 0.36, saturation: 0.70, brightness: 0.92)
                                    ],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                    }

                    Text("Wellcome!")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                }

                // Invite code capsule with copy
                CopyCapsule(ref: ref, copied: $copied)

                // CTA
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                    onClaim(ref)
                } label: {
                    Text("Let׳s Start")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .padding(.vertical, 14).frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GradientButtonStyle(pressed: $press))

                // Tiny note
                Text("By joining, you agree to the Terms and Privacy Policy.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial) // glass card
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
            )
            .padding(.horizontal, 20)

            // Toast
            if copied {
                ToastView(text: "Copied code", systemImage: "checkmark.circle.fill")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }

    // MARK: Subviews

    private struct CopyCapsule: View {
        let ref: String
        @Binding var copied: Bool

        var body: some View {
            VStack(spacing: 10) {
                Text("You were invited by")
                    .foregroundStyle(.white.opacity(0.75))
                    .font(.footnote.weight(.semibold))

                Text(verbatim: ref)
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)

            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1))
            )
        }
    }

    private struct ToastView: View {
        let text: LocalizedStringKey
        let systemImage: String
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: systemImage).foregroundStyle(.white)
                Text(text)
                    .foregroundStyle(.white)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.black.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
            .padding(.top, 14)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Gradient Button Style

private struct GradientButtonStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: 0.40, saturation: 0.82, brightness: 0.62), // darker emerald
                                Color(hue: 0.36, saturation: 0.72, brightness: 0.90)  // mint bright
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            .onChange(of: configuration.isPressed) { _, v in pressed = v }
    }
}
