//
//  SubscriptionPaywallView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 14/09/2025.
//

import SwiftUI

// MARK: - Paywall (Hub style)

struct SubscriptionPaywallView: View {
    // Control presentation without closures
    @Binding var isPresented: Bool
    
    // Use your manager directly (no closures)
    @EnvironmentObject private var premium: PremiumManager
    
    // Local UI state
    @State private var selected: PremiumPlan = .yearly
    @State private var shimmer = false
    
    var body: some View {
        ZStack(alignment: .center) {
            // Background – match Hub
            LinearGradient(colors: [Color.black,
                                    Color(hue: 0.64, saturation: 0.25, brightness: 0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            // Soft neon glow behind the card (no GeometryReader needed)
            RadialGradient(
                gradient: Gradient(colors: [HubPaywallPalette.accent.opacity(0.22), .clear]),
                center: .center,
                startRadius: 40,
                endRadius: 520
            )
            .blur(radius: 80)
            .allowsHitTesting(false)
            
            // Card
            VStack(spacing: 18) {
                header
                
                FeatureRow(icon: "sparkles",   text: "Exclusive Mini-Games – Access fun and challenging modes only in the Hub.".localized)
                FeatureRow(icon: "crown.fill", text: "Play unique twists that go beyond regular gameplay.".localized)
                FeatureRow(icon: "bolt.fill",  text: "Compete with other premium players for top ranks.".localized)
                FeatureRow(icon: "umbrella",   text: "Ad-Free Play – Smooth, uninterrupted gaming inside the Hub.".localized)
                
                PlanPickerHubStyle(
                    selected: $selected,
                    monthlyPrice: premium.monthlyPriceText,
                    yearlyPrice: premium.yearlyPriceText,
                    yearlyBadgeText: premium.yearlyBadgeText,
                    trialText: premium.trialText
                )
                
                ctaButton
                footerLinks
            }
            .padding(22)
            .background(
                // glassy card like hub tiles
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(HubPaywallPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(HubPaywallPalette.stroke, lineWidth: 1)
            )
            .shadow(color: HubPaywallPalette.glow, radius: 26, y: 14)
            .overlay(alignment: .topTrailing) { closeButton }
            .overlay(
                ShimmerSweep(trigger: $shimmer)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .opacity(0.35)
            )
            .onAppear {
                // little attention ping
                withAnimation(.easeOut(duration: 0.08)) { shimmer = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    withAnimation(.easeOut(duration: 0.08)) { shimmer = false }
                }
            }
            // ⬇️ Constrain width, give safe margins, and center within screen
            .frame(maxWidth: 560)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .tint(.white)
        .disabled(premium.isPurchasing)
    }
    
    // MARK: Sections
    
    private var header: some View {
        VStack(spacing: 10) {
            PremiumCrownHub()
                .frame(width: 64, height: 64)
                .shadow(color: HubPaywallPalette.accent.opacity(0.6), radius: 14, y: 8)
            
            Text("Go Premium")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            
            Text("Unlock all features, no ads, daily challenges, and more.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal)
        }
    }
    
    private var ctaButton: some View {
        Button {
            guard !premium.isPurchasing else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { @MainActor in
                premium.isPurchasing = true
                defer { premium.isPurchasing = false }
                await premium.purchase(selected)
                isPresented = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.fill")
                Text(ctaText(for: selected, trialText: premium.trialText).localized)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(AccentGlassyButtonStyle())
        .overlay {
            if premium.isPurchasing {
                ProgressView().progressViewStyle(.circular)
            }
        }
        .disabled(premium.isPurchasing)
        .accessibilityLabel("Subscribe \(ctaText(for: selected, trialText: premium.trialText))")
    }
    
    private var footerLinks: some View {
        HStack(spacing: 16) {
            Button("Restore Purchases") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await premium.restore() }
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.7))
            .buttonStyle(.plain)
            
            Text("•").foregroundStyle(.white.opacity(0.35))
            
            Link("Terms", destination: URL(string: "https://barakbenhur1.github.io/terms.html")!)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            
            Text("•").foregroundStyle(.white.opacity(0.35))
            
            Link("Privacy", destination: URL(string: "https://barakbenhur1.github.io/privacy.html")!)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 2)
    }
    
    private var closeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .padding(10)
                .background(HubPaywallPalette.card, in: Circle())
                .overlay(Circle().stroke(HubPaywallPalette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.trailing, 12)
        .accessibilityLabel("Close")
    }
    
    // MARK: Helpers
    
    private func ctaText(for plan: PremiumPlan, trialText: String?) -> String {
        switch plan {
        case .monthly: return trialText.map { "Start \($0)" } ?? "Subscribe Monthly".localized
        case .yearly:  return trialText.map { "Start \($0)" } ?? "Subscribe Yearly".localized
        }
    }
}

// MARK: - Pieces (Hub style)

private struct PremiumCrownHub: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            // Accent halo
            Circle()
                .stroke(LinearGradient(colors: [HubPaywallPalette.accent, HubPaywallPalette.accent2],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2)
                .blur(radius: 1.5)
                .opacity(0.9)
            // Pulsing ring
            Circle()
                .stroke(HubPaywallPalette.accent.opacity(0.6), lineWidth: 2)
                .scaleEffect(pulse ? 1.25 : 0.9)
                .opacity(pulse ? 0.0 : 0.6)
                .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: pulse)
                .onAppear { pulse = true }
            // Chip + crown
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
            Image(systemName: "crown.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(LinearGradient(colors: [HubPaywallPalette.accent, HubPaywallPalette.accent2],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .font(.system(size: 30, weight: .bold))
                .shadow(color: HubPaywallPalette.accent.opacity(0.6), radius: 8, y: 4)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(colors: [HubPaywallPalette.accent.opacity(0.35),
                                            HubPaywallPalette.accent2.opacity(0.25)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.25), lineWidth: 1))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlanPickerHubStyle: View {
    @Binding var selected: PremiumPlan
    var monthlyPrice: String
    var yearlyPrice: String
    var yearlyBadgeText: String?
    var trialText: String?
    
    var body: some View {
        VStack(spacing: 12) {
            planRow(.yearly,
                    title: "Yearly",
                    subtitle: "\("Just".localized) \(formattedPerMonth(from: yearlyPrice).localized)\("/mo".localized)",
                    price: yearlyPrice,
                    badge: yearlyBadgeText ?? "Best value".localized)
            planRow(.monthly,
                    title: "Monthly",
                    subtitle: nil,
                    price: monthlyPrice,
                    badge: nil)
        }
    }
    
    @ViewBuilder
    private func planRow(_ plan: PremiumPlan,
                         title: String,
                         subtitle: String?,
                         price: String,
                         badge: String?) -> some View {
        let isSelected = (selected == plan)
        
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                selected = plan
            }
        } label: {
            HStack(spacing: 14) {
                // Radio
                ZStack {
                    Circle().strokeBorder(.white.opacity(0.30), lineWidth: 1)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(LinearGradient(colors: [HubPaywallPalette.accent, HubPaywallPalette.accent2],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 12, height: 12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title.localized).font(.headline.weight(.semibold)).foregroundStyle(.white)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(
                                    LinearGradient(colors: [HubPaywallPalette.accent.opacity(0.95),
                                                            HubPaywallPalette.accent2.opacity(0.95)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .foregroundStyle(.black)
                                .clipShape(Capsule())
                        }
                    }
                    if let subtitle {
                        Text(subtitle.localized)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer()
                Text(price.localized)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HubPaywallPalette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                AnyShapeStyle(
                                    isSelected
                                    ? AnyShapeStyle(LinearGradient(
                                        colors: [HubPaywallPalette.accent, HubPaywallPalette.accent2],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    : AnyShapeStyle(HubPaywallPalette.stroke)
                                ),
                                lineWidth: isSelected ? 1.6 : 1.0
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) plan \(price)")
    }
    
    private func formattedPerMonth(from yearly: String, locale: Locale = .current) -> String {
        // Extract only digits, dots, and commas
        let digits = yearly.replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
        // Normalize commas to dots for Double parsing
        let normalized = digits.replacingOccurrences(of: ",", with: ".")
        
        guard let value = Double(normalized) else {
            let nf = NumberFormatter()
            nf.numberStyle = .currency
            nf.locale = locale
            return nf.string(from: 0) ?? nf.currencySymbol + "—"
        }
        
        let perMonth = value / 12.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        
        return formatter.string(from: NSNumber(value: perMonth)) ?? formatter.currencySymbol + "—"
    }
}

// MARK: - Styles / Palette (Hub-like)

private struct AccentGlassyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(colors: [HubPaywallPalette.accent, HubPaywallPalette.accent2],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(configuration.isPressed ? 0.95 : 1)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .shadow(color: HubPaywallPalette.glow, radius: configuration.isPressed ? 8 : 14, y: 8)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// local palette echoing the hub’s look
private enum HubPaywallPalette {
    static let card   = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.09)
    static let glow   = Color.white.opacity(0.22)
    static let accent = Color.cyan
    static let accent2 = Color.mint
}

// Reuse shimmer sweep from the hub (inline to avoid imports)
private struct ShimmerSweep: View {
    @Binding var trigger: Bool
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Rectangle()
                .fill(
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: .white.opacity(0.0),  location: 0.00),
                        .init(color: .white.opacity(0.10), location: 0.45),
                        .init(color: .white.opacity(0.45), location: 0.50),
                        .init(color: .white.opacity(0.10), location: 0.55),
                        .init(color: .white.opacity(0.00), location: 1.00),
                    ]), startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: w * 0.42)
                .rotationEffect(.degrees(24))
                .offset(x: trigger ? w*1.05 : -w*1.05)
                .animation(.easeOut(duration: 0.08), value: trigger)
        }
        .allowsHitTesting(false)
        .blendMode(.plusLighter)
    }
}

private extension NumberFormatter {
    static let currencyIL: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "ILS"
        f.maximumFractionDigits = 2
        return f
    }()
}

// MARK: - Preview

struct SubscriptionPaywallView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionPaywallView(isPresented: .constant(true))
            .environmentObject(PremiumManager.shared) // preview stub
            .preferredColorScheme(.dark)
            .frame(maxHeight: .infinity)
            .background(
                LinearGradient(colors: [Color.black,
                                        Color(hue: 0.64, saturation: 0.25, brightness: 0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            )
    }
}
