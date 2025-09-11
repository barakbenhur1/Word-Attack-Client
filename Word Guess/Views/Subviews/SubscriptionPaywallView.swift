import SwiftUI

// MARK: - Paywall

struct SubscriptionPaywallView: View {
    // Control presentation without closures
    @Binding var isPresented: Bool
    
    // Use your manager directly (no closures)
    @EnvironmentObject private var premium: PremiumManager
    
    // Local UI state
    @State private var selected: PremiumPlan = .yearly
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(colors: [.black, .indigo.opacity(0.9), .purple.opacity(0.9)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            // Glow
            Circle()
                .stroke(lineWidth: 2)
                .fill(RadialGradient(colors: [.purple.opacity(0.6), .clear],
                                     center: .center, startRadius: 20, endRadius: 280))
                .frame(width: 420, height: 420)
                .blur(radius: 40)
                .opacity(0.7)
                .offset(y: -160)
                .allowsHitTesting(false)
            
            // Card
            VStack(spacing: 18) {
                header
                
                FeatureRow(icon: "sparkles",   text: "AI Word Assistant & smart hints")
                FeatureRow(icon: "crown.fill", text: "Pro challenges & exclusive modes")
                FeatureRow(icon: "bolt.fill",  text: "Faster gameplay with no limits")
                FeatureRow(icon: "umbrella",   text: "Ad-free, zen experience")
                
                PlanPicker(selected: $selected,
                           monthlyPrice: premium.monthlyPriceText,
                           yearlyPrice: premium.yearlyPriceText,
                           yearlyBadgeText: premium.yearlyBadgeText,
                           trialText: premium.trialText)
                
                ctaButton
                
                footerLinks
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 20)
            .padding(.horizontal, 20)
            .overlay(alignment: .topTrailing) { closeButton }
            .padding(.vertical, 18)
        }
        .tint(.white)
        .disabled(premium.isPurchasing)
    }
    
    // MARK: Sections
    
    private var header: some View {
        VStack(spacing: 8) {
            PremiumCrown()
                .frame(width: 56, height: 56)
                .shadow(radius: 8, y: 6)
            
            Text("Go Premium")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            
            Text("Unlock all features, no ads, daily challenges, and more.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
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
                await premium.purchase(selected) // ← uses your manager (no closures)
                isPresented = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.fill")
                Text(ctaText(for: selected, trialText: premium.trialText))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassyButtonStyle())
        .overlay {
            if premium.isPurchasing { ProgressView().progressViewStyle(.circular) }
        }
        .disabled(premium.isPurchasing)
        .accessibilityLabel("Subscribe \(ctaText(for: selected, trialText: premium.trialText))")
    }
    
    private var footerLinks: some View {
        HStack(spacing: 16) {
            Button("Restore Purchases") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await premium.restore() } // ← uses your manager
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            
            Text("•").foregroundStyle(.tertiary)
            
            // TODO: Replace URLs
            Link("Terms", destination: URL(string: "https://example.com/terms")!)
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            Text("•").foregroundStyle(.tertiary)
            
            Link("Privacy", destination: URL(string: "https://example.com/privacy")!)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.trailing, 12)
        .accessibilityLabel("Close")
    }
    
    // MARK: Helpers
    
    private func ctaText(for plan: PremiumPlan, trialText: String?) -> String {
        switch plan {
        case .monthly: return trialText.map { "Start \($0)" } ?? "Subscribe Monthly"
        case .yearly:  return trialText.map { "Start \($0)" } ?? "Subscribe Yearly"
        }
    }
}

// MARK: - Pieces

private struct PremiumCrown: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.yellow.opacity(0.35), .orange.opacity(0.15)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                .shadow(radius: 8, y: 6)
            Image(systemName: "crown.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.yellow, .orange)
                .font(.system(size: 30, weight: .bold))
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
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(colors: [.purple.opacity(0.35), .indigo.opacity(0.25)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.25), lineWidth: 1))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlanPicker: View {
    @Binding var selected: PremiumPlan
    var monthlyPrice: String
    var yearlyPrice: String
    var yearlyBadgeText: String?
    var trialText: String?
    
    var body: some View {
        VStack(spacing: 12) {
            planRow(.yearly,
                    title: "Yearly",
                    subtitle: "Just \(formattedPerMonth(from: yearlyPrice))/mo",
                    price: yearlyPrice,
                    badge: yearlyBadgeText)
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
                    Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(LinearGradient(colors: [.purple, .pink],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 12, height: 12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(LinearGradient(colors: [.yellow.opacity(0.9), .orange.opacity(0.9)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                                .foregroundStyle(.black)
                                .clipShape(Capsule())
                        }
                    }
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(price)
                    .font(.headline.monospacedDigit())
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected
                                    ? LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : .linearGradient(colors: [.white.opacity(0.25), .white.opacity(0.05)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) plan \(price)")
    }
    
    private func formattedPerMonth(from yearly: String) -> String {
        let digits = yearly.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        if let value = Double(digits) {
            let perMonth = value / 12.0
            let number = NSNumber(value: perMonth)
            return NumberFormatter.currencyIL.string(from: number) ?? "₪—"
        }
        return "₪—"
    }
}

private struct GlassyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.yellow.opacity(0.95), .orange.opacity(0.95)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .opacity(configuration.isPressed ? 0.95 : 1)
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

// MARK: - Usage / Preview

struct SubscriptionPaywallView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionPaywallView(isPresented: .constant(true))
            .environmentObject(PremiumManager.shared) // preview stub
            .preferredColorScheme(.dark)
    }
}
