//
//  SubscriptionPaywallView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 14/09/2025.
//

import SwiftUI
import StoreKit

// MARK: - Paywall (Hub style)

struct SubscriptionPaywallView: View {
    // Control presentation without closures
    @Binding var isPresented: Bool
    
    // Use your manager directly (no closures)
    @EnvironmentObject private var premium: PremiumManager
    @Environment(\.colorScheme) private var scheme
    
    // Local UI state
    @State private var selected: PremiumPlan?
    @State private var shimmer = false
    
    // Anti-glitch
    @State private var firstFrame = true
    @State private var hasAppeared = false
    
    var body: some View {
        ZStack(alignment: .center) {
            // Background – adapts to light/dark
            HubPaywallPalette.bgGradient(scheme)
                .ignoresSafeArea()
            
            // Soft neon glow behind the card
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
                    .frame(maxHeight: 180)
                
                FeatureRow(icon: "sparkles",
                           text: "Exclusive Mini-Games – Access fun and challenging modes only in the Hub.".localized)
                FeatureRow(icon: "square.stack.3d.up.fill",
                           text: "Play unique twists that go beyond regular gameplay.".localized)
                FeatureRow(icon: "bolt.fill",
                           text: "Compete with other premium players for top ranks.".localized)
                FeatureRow(icon: "umbrella",
                           text: "Ad-Free Play – Smooth, uninterrupted gaming inside the Hub.".localized)
                
                PlanPickerHubStyle(
                    selected: $selected,
                    monthlyPrice: premium.monthlyPriceText,
                    yearlyPrice: premium.yearlyPriceText,
                    yearlyBadgeText: premium.yearlyBadgeText,
                    trialText: nil, // legacy, not used
                    monthlyTrial: premium.monthlyTrialText,
                    yearlyTrial: premium.yearlyTrialText
                )
                
                ctaButton
                footerLinks
            }
            .padding(22)
            .background(
                // glassy card like hub tiles
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(HubPaywallPalette.card(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(HubPaywallPalette.stroke(scheme), lineWidth: 1)
            )
            .shadow(color: HubPaywallPalette.glow(scheme), radius: 26, y: 14)
            .overlay(alignment: .topTrailing) { closeButton }
//            .overlay(
//                ShimmerSweep(trigger: $shimmer)
//                    .clipShape(RoundedRectangle(cornerRadius: 28))
//                    .opacity(0.35)
//            )
            // first render fade-in to hide late text swaps
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: hasAppeared)
            // do NOT animate incoming price/trial strings
            .animation(nil, value: premium.monthlyPriceText)
            .animation(nil, value: premium.yearlyPriceText)
            .animation(nil, value: premium.monthlyTrialText)
            .animation(nil, value: premium.yearlyTrialText)
            // ⬇️ Constrain width, give safe margins, and center within screen
            .frame(maxWidth: 560)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .tint(HubPaywallPalette.tint(scheme))
        .disabled(premium.isPurchasing)
        .task {
            // Ensure products & trial strings are loaded
            await premium.loadProducts()
            
            // On very first layout, select without animation to avoid jump
            if firstFrame {
                withAnimation(.none) {
                    if premium.yearlyTrialText != nil {
                        selected = .yearly
                    } else if premium.monthlyTrialText != nil {
                        selected = .monthly
                    }
                }
                firstFrame = false
            }
        }
        .onAppear {
            hasAppeared = true
            // Start shimmer after layout settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeOut(duration: 0.10)) { shimmer = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.10)) { shimmer = false }
                }
            }
        }
    }
    
    // MARK: Sections
    
    private var header: some View {
        VStack(spacing: 10) {
            PremiumCrownHub()
                .frame(width: 72, height: 72)
                .cornerRadius(36)
                .shadow(color: HubPaywallPalette.accent.opacity(0.6), radius: 14, y: 8)
            
            Text("Go Premium")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(HubPaywallPalette.textPrimary(scheme))
                .accessibilityAddTraits(.isHeader)
            
            Text("Unlock all features, no ads, daily challenges, and more.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(HubPaywallPalette.textSecondary(scheme))
                .padding(.horizontal)
        }
    }
    
    private var ctaButton: some View {
        Button {
            guard let selected else { return }
            guard !premium.isPurchasing else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { @MainActor in
                premium.isPurchasing = true
                defer { premium.isPurchasing = false }
                await premium.purchase(selected)
                if premium.justDone || premium.isPremium {
                    isPresented = false
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected != nil ? "lock.open.fill" : "lock.fill")
                Text(ctaText(for: selected, trialText: premium.trialText).localized)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true) // stable height
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(AccentGlassyButtonStyle())
        .overlay {
            if premium.isPurchasing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(scheme == .dark ? .white : .black)
            }
        }
        // Disable until products load at least once + a plan is chosen
        .disabled(
            selected == nil ||
            premium.isPurchasing ||
            (premium.monthlyPriceText == "—" && premium.yearlyPriceText == "—")
        )
        .accessibilityLabel("Subscribe \(ctaText(for: selected, trialText: premium.trialText))")
    }
    
    private var footerLinks: some View {
        HStack(spacing: 16) {
            Button("Restore Purchases") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await premium.restore() }
            }
            .font(.footnote)
            .foregroundStyle(HubPaywallPalette.textSecondary(scheme))
            .buttonStyle(.plain)
            
            Text("•").foregroundStyle(HubPaywallPalette.divider(scheme))
            
            Link("Terms", destination: URL(string: "https://barakbenhur1.github.io/terms.html")!)
                .font(.footnote)
                .foregroundStyle(HubPaywallPalette.textSecondary(scheme))
            
            Text("•").foregroundStyle(HubPaywallPalette.divider(scheme))
            
            Link("Privacy", destination: URL(string: "https://barakbenhur1.github.io/privacy.html")!)
                .font(.footnote)
                .foregroundStyle(HubPaywallPalette.textSecondary(scheme))
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
                .background(HubPaywallPalette.card(scheme), in: Circle())
                .overlay(Circle().stroke(HubPaywallPalette.stroke(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.trailing, 12)
        .accessibilityLabel("Close")
    }
    
    // MARK: Helpers
    
    private func ctaText(for plan: PremiumPlan?, trialText: String?) -> String {
        guard let plan else {
            return "\("Subscribe".localized)\(trialText != nil ? "\n" + trialText! : "")"
        }
        switch plan {
        case .monthly:
            let trial = premium.monthlyTrialText ?? ""
            return trial.isEmpty ? "Subscribe Monthly".localized
            : "\("Subscribe Monthly Get".localized) \(trial)"
        case .yearly:
            let trial = premium.yearlyTrialText ?? ""
            return trial.isEmpty ? "Subscribe Yearly".localized
            : "\("Subscribe Yearly Get".localized) \(trial)"
        }
    }
}

// MARK: - Pieces (Hub style)

private struct PremiumCrownHub: View {
    @Environment(\.colorScheme) private var scheme
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
                .fill(
                    scheme == .dark
                    ? LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    Circle().stroke(
                        (scheme == .dark ? Color.black : Color.white).opacity(0.25),
                        lineWidth: 1
                    )
                )
            Image(systemName: "crown.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(LinearGradient(colors: [HubPaywallPalette.accent, HubPaywallPalette.accent2],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .font(.system(size: 30, weight: .bold))
                .shadow(color: HubPaywallPalette.accent.opacity(0.6), radius: 8, y: 4)
        }
        .padding(8)
    }
}

private struct FeatureRow: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HubPaywallPalette.icon(scheme))
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(colors: [HubPaywallPalette.accent.opacity(0.35),
                                            HubPaywallPalette.accent2.opacity(0.25)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(HubPaywallPalette.overlayStroke(scheme), lineWidth: 1))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(HubPaywallPalette.textPrimary(scheme))
                .opacity(0.92)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlanPickerHubStyle: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selected: PremiumPlan?
    var monthlyPrice: String
    var yearlyPrice: String
    var yearlyBadgeText: String?
    var trialText: String? // legacy, not used here
    var monthlyTrial: String?
    var yearlyTrial: String?
    
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
                    Circle().strokeBorder(HubPaywallPalette.radioStroke(scheme), lineWidth: 1)
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
                        Text(title.localized)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(HubPaywallPalette.textPrimary(scheme))
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
                            .foregroundStyle(HubPaywallPalette.textSecondary(scheme))
                    }
                    // Per-plan trial hint: always reserve line height
                    if let t = (plan == .yearly ? yearlyTrial : monthlyTrial), !t.isEmpty {
                        Text(t.localized)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(HubPaywallPalette.textSecondary(scheme))
                    } else {
                        Text("Placeholder")
                            .font(.caption2.weight(.semibold))
                            .hidden()
                    }
                }
                Spacer()
                Text(price.localized)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(HubPaywallPalette.textPrimary(scheme))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HubPaywallPalette.card(scheme))
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
                                    : AnyShapeStyle(HubPaywallPalette.stroke(scheme))
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
    @Environment(\.colorScheme) private var scheme
    
    func makeBody(configuration: Configuration) -> some View {
        let stroke = scheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.15)
        let glow   = scheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.10)
        
        return configuration.label
            .font(.headline)
            .foregroundStyle(HubPaywallPalette.buttonLabel(scheme))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(colors: [.cyan, .mint],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(configuration.isPressed ? 0.95 : 1)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .shadow(color: glow, radius: configuration.isPressed ? 8 : 14, y: 8)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// Adaptive palette for light/dark keeping your dark design as-is
private enum HubPaywallPalette {
    // Accents stay the same in both modes
    static let accent  = Color.cyan
    static let accent2 = Color.mint
    
    static func bgGradient(_ scheme: ColorScheme) -> LinearGradient {
        switch scheme {
        case .dark:
            return LinearGradient(
                colors: [Color.black,
                         Color(hue: 0.64, saturation: 0.25, brightness: 0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [Color(UIColor.systemGroupedBackground),
                         Color(UIColor.secondarySystemGroupedBackground)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
    
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color.white.opacity(0.06)
        : Color.white.opacity(0.92)
    }
    
    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color.white.opacity(0.09)
        : Color.black.opacity(0.08)
    }
    
    static func overlayStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color.white.opacity(0.25)
        : Color.black.opacity(0.15)
    }
    
    static func radioStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color.white.opacity(0.30)
        : Color.black.opacity(0.25)
    }
    
    static func glow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color.white.opacity(0.22)
        : Color.black.opacity(0.10)
    }
    
    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }
    
    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6)
    }
    
    static func icon(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }
    
    static func divider(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.35) : .black.opacity(0.35)
    }
    
    static func buttonLabel(_ scheme: ColorScheme) -> Color {
        // Black on cyan/mint reads well in both modes
        .black
    }
    
    static func tint(_ scheme: ColorScheme) -> Color {
        // Control tint (links, switches, etc.)
        scheme == .dark ? .white : .black
    }
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
                .animation(.easeOut(duration: 0.10), value: trigger)
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
        Group {
            SubscriptionPaywallView(isPresented: .constant(true))
                .environmentObject(PremiumManager.shared)
                .preferredColorScheme(.dark)
                .frame(maxHeight: .infinity)
                .background(HubPaywallPalette.bgGradient(.dark).ignoresSafeArea())
            
            SubscriptionPaywallView(isPresented: .constant(true))
                .environmentObject(PremiumManager.shared)
                .preferredColorScheme(.light)
                .frame(maxHeight: .infinity)
                .background(HubPaywallPalette.bgGradient(.light).ignoresSafeArea())
        }
    }
}
