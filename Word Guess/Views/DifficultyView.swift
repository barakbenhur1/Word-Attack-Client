//
//  DifficultyView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI

@Observable
class MenuManager: ObservableObject {
    var id = UUID()
    
    func refresh() {
        id = UUID()
    }
}

struct DifficultyButton: Identifiable {
    var id = UUID()
    let type: DifficultyType
}

enum DifficultyType: String, Codable, CaseIterable {
    case ai = "⚔️ AI", easy = "😀 Easy", medium = "😳 Medium", hard = "🥵 Hard", tutorial
    
    init?(stripedRawValue: String) {
        switch stripedRawValue.lowercased() {
        case "easy": self = .easy
        case "medium": self = .medium
        case "hard": self = .hard
        default: return nil
        }
    }
    
    var stringValue: String { rawValue.localized }
    
    var liveValue: Difficulty {
        switch self {
        case .easy: return .easy
        case .medium: return .medium
        case .hard: return .hard
        default: fatalError()
        }
    }
    
    func getLength() -> Int {
        switch self {
        case .easy, .tutorial: return 4
        case .medium, .ai:     return 5
        case .hard:            return 6
        }
    }
}

// MARK: - View

struct DifficultyView: View {
    @FetchRequest(sortDescriptors: []) var tutorialItems: FetchedResults<TutorialItem>
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var premium: PremiumManager
    
    @State private var isMenuOpen: Bool
    @State private var showPaywall: Bool
    @State private var isOpen: Bool
    @State private var text: String
    
    private let menuManager: MenuManager = .init()
    private var tutorialItem: TutorialItem? { tutorialItems.first }
    private let auth = Authentication()
    
    init() {
        isMenuOpen = false
        showPaywall = false
        isOpen = true
        text = ""
    }
    
    private let buttons: [DifficultyButton] = [
        .init(type: .easy),
        .init(type: .medium),
        .init(type: .hard),
    ]
    
    private func onAppear() {
        audio.stopAudio(true)
        task()
    }
    private func onDisappear() { audio.stopAudio(false) }
    private func task() {
        guard tutorialItem == nil else { return }
        router.navigateTo(.game(diffculty: .tutorial))
    }
    
    var body: some View {
        SlidingDoorOpen(isOpen: $isOpen, text: text, duration: 1.2) {
            ZStack {
                GeometryReader { _ in
                    BackgroundDecor().ignoresSafeArea()
                    ZStack {
                        contant()
                            .onDisappear { onDisappear() }
                            .onAppear { onAppear() }
                            .ignoresSafeArea(.keyboard)
                            .fullScreenCover(isPresented: $showPaywall) {
                                SubscriptionPaywallView(isPresented: $showPaywall)
                            }
                    }
                    SideMenu(isOpen: $isMenuOpen,
                             content: { SettingsView(fromSideMenu: true) })
                    .id(menuManager.id)
                    .ignoresSafeArea()
                    .environmentObject(menuManager)
                }
            }
            .onAppear {
                text = ""
                withAnimation(.interpolatingSpring(duration: 1.2)) {
                    isOpen = true
                }
            }
        }
        .ignoresSafeArea(.keyboard)
    }
    
    // MARK: - Content
    @ViewBuilder private func contant() -> some View {
        ZStack(alignment: .top) {
            VStack {
                topButtons()
                    .padding(.vertical, 10)
                buttonList()
            }
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .top) {
            AdProvider.adView(id: "TopBanner", withPlaceholder: true)
                .frame(minHeight: 40, maxHeight: 50)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
        }
        .safeAreaInset(edge: .bottom) {
            AdProvider.adView(id: "BottomBanner", withPlaceholder: true)
                .frame(minHeight: 40, maxHeight: 50)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
        }
    }
    
    @ViewBuilder private func topButtons() -> some View {
        HStack(spacing: 16) {
            TopTileButton(
                title: "Settings",
                icon: Image(systemName: "gearshape.fill"),
                action: {
                    Task.detached {
                        await MainActor.run {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { isMenuOpen = true }
                        }
                    }
                }
            )
            .frame(maxWidth: .infinity)
            
            TopTileButton(
                title: "SCOREBOARD",
                icon: Image(systemName: "person.3.fill"),
                action: { router.navigateToSync(.score) }
            )
            .frame(maxWidth: .infinity)
            
            TopTileButton(
                title: "Premium Hub",
                icon: PremiumBadge()
                    .grayscale(premium.isPremium ? 0 : 1)
                    .font(.system(size: 28, weight: .semibold)),
                action: {
                    if premium.isPremium {
                        text = "Premium Hub  💎"
                        withAnimation(.interpolatingSpring(duration: 1.2)) {
                            isOpen = false
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            router.navigateToSync(.premium(uniqe: loginHandeler.model?.uniqe))
                        }
                    }
                    else { showPaywall = true }
                },
                isLocked: !premium.isPremium // <-- locked style but still tappable
            )
            .tileAvailability(isEnabled: premium.isPremium) // sunken when locked
            .shadow(color: .yellow.opacity(premium.isPremium ? 0.35 : 0.0),
                    radius: premium.isPremium ? 4 : 0, y: 3)
            .frame(maxWidth: .infinity)
            .attentionIfNew(isActive: $premium.justDone)
        }
        .padding(.horizontal, 4)
    }
    
    @ViewBuilder private func buttonList() -> some View {
        VStack {
            GlassContainer(corner: 32) {
                VStack(spacing: 6) {
                    difficultyButton(type: .ai)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    
                    title()
                        .padding(.top, 2)
                    
                    ForEach(buttons) { button in
                        difficultyButton(type: button.type)
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    }
                }
                .padding(14)
                .padding(.vertical, 4)
            }
            .padding(.top, 6)
            
            logoutButton()
                .padding(.all, 10)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
    }
    
    @ViewBuilder private func title() -> some View {
        VStack(spacing: 2) {
            Text("DIFFICULTY")
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundStyle(Color.dynamicBlack)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            
            Text("Pick a challenge to begin")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .scale))
        }
        .padding(.bottom, 6)
    }
    
    @ViewBuilder private func difficultyButton(type: DifficultyType) -> some View {
        let style: ElevatedButtonStyle = {
            switch type {
            case .easy:   ElevatedButtonStyle(palette: .green)
            case .medium: ElevatedButtonStyle(palette: .amber)
            case .hard:   ElevatedButtonStyle(palette: .rose)
            case .ai:     ElevatedButtonStyle(palette: .teal)
            default:      ElevatedButtonStyle()
            }
        }()
        
        Button {
            router.navigateToSync(.game(diffculty: type))
        } label: {
            ElevatedButtonLabel(LocalizedStringKey(type.rawValue))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(style)
        .scaleEffectOnPress()
        .accessibilityLabel(Text(type.stringValue))
    }
    
    @ViewBuilder private func logoutButton() -> some View {
        Button {
            Task.detached(priority: .userInitiated) {
                await MainActor.run {
                    loginHandeler.model = nil
                    auth.logout()
                }
            }
        } label: {
            ElevatedButtonLabel(LocalizedStringKey("👋 Logout"))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(ElevatedButtonStyle(palette: .slate))
        .scaleEffectOnPress()
    }
}

// MARK: - Premium badge (kept)

private struct PremiumBadge: View {
    var body: some View {
        Image(systemName: "crown.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.yellow, .orange)
            .font(.system(size: 32, weight: .semibold))
            .shadow(color: .yellow.opacity(0.35), radius: 8, x: 0, y: 2)
            .accessibilityLabel("Premium")
    }
}

// MARK: - Background (subtle motion)
private struct BackgroundDecor: View {
    @Environment(\.colorScheme) private var scheme
    @State private var t: CGFloat = 0
    
    private let seam: Double = 0.012
    
    private var conicStopsDark: [Gradient.Stop] {
        [
            .init(color: .purple.opacity(0.20), location: 0.00),
            .init(color: .purple.opacity(0.20), location: seam),        // guard band start
            .init(color: .cyan.opacity(0.16),   location: 0.25),
            .init(color: .pink.opacity(0.18),   location: 0.50),
            .init(color: .mint.opacity(0.16),   location: 0.75),
            .init(color: .purple.opacity(0.20), location: 1.0 - seam),   // guard band end
            .init(color: .purple.opacity(0.20), location: 1.00)
        ]
    }
    
    private var conicStopsLight: [Gradient.Stop] {
        [
            .init(color: .purple.opacity(0.12), location: 0.00),
            .init(color: .purple.opacity(0.12), location: seam),
            .init(color: .cyan.opacity(0.09),   location: 0.25),
            .init(color: .pink.opacity(0.10),   location: 0.50),
            .init(color: .mint.opacity(0.09),   location: 0.75),
            .init(color: .purple.opacity(0.12), location: 1.0 - seam),
            .init(color: .purple.opacity(0.12), location: 1.00)
        ]
    }
    
    var body: some View {
        ZStack {
            // Base gradient (adaptive)
            LinearGradient(
                colors: baseGradient,
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(
                AngularGradient(
                    gradient: Gradient(stops: scheme == .dark ? conicStopsDark : conicStopsLight),
                    center: .center,
                    angle: .degrees(Double(t) * 360
                                    + 0.7
                                    + sin(Double(t) * .pi * 2 * 0.25) * 0.8)
                )
                // breathing + blur
                .scaleEffect(1.08 + CGFloat(sin(Double(t) * .pi * 2 * 0.14)) * 0.006)
                .compositingGroup()
                .blur(radius: scheme == .dark ? 24 : 28, opaque: true)
                // blend softer in light mode to avoid washing out
                .blendMode(scheme == .dark ? .screen : .plusLighter)
                // reduce lift in light mode
                .opacity(scheme == .dark ? 0.30 : 0.20)
                // keep energy near center
                .mask(
                    RadialGradient(
                        colors: [.white.opacity(1.0), .white.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: scheme == .dark ? 1050 : 1150
                    )
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white,               location: 0.00),
                            .init(color: .white,               location: 0.64),
                            .init(color: .white.opacity(0.75), location: 0.86),
                            .init(color: .clear,               location: 1.00)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .animation(.linear(duration: 22).repeatForever(autoreverses: false), value: t)
            )
            .onAppear { t = 1 }
            
            // Vignette (lighter in light mode, multiply so whites stay crisp)
            Group {
                if scheme == .dark {
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.30)],
                        center: .center, startRadius: 0, endRadius: 1200
                    )
                } else {
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.08)],
                        center: .center, startRadius: 0, endRadius: 1200
                    )
                    .blendMode(.multiply)
                }
            }
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.25), value: scheme) // smooth Light/Dark switch
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Palettes
    private var baseGradient: [Color] {
        if scheme == .dark {
            // your original dark base
            [Color(hex: 0x10131B), Color(hex: 0x151A26)]
        } else {
            // airy neutrals with a cool hint
            [
                Color(red: 0.97, green: 0.98, blue: 1.00),
                Color(red: 0.95, green: 0.98, blue: 1.00)
            ]
        }
    }
}


// MARK: - Glass container

struct GlassContainer<Content: View>: View {
    var corner: CGFloat = 32
    @ViewBuilder var content: Content
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 12)
                        .blur(radius: 16)
                        .blendMode(.overlay)
                )
            content
        }
    }
}

// MARK: - Top tile button (now supports locked styling)

private struct TopTileButton<Icon: View>: View {
    let title: String
    let icon: Icon
    var action: () -> Void
    var isLocked: Bool = false   // NEW
    
    private let tileSize: CGFloat = 60
    private let corner: CGFloat = 16
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .stroke(.black.opacity(0.22), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    
                    icon
                        .foregroundStyle(.primary.opacity(0.92))
                        .frame(width: tileSize - 24, height: tileSize - 24)
                }
                .frame(width: tileSize, height: tileSize)
                
                Text(title.localized)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary.opacity(isLocked ? 0.55 : 1))
                    .shadow(color: .primary.opacity(0.55), radius: 2, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pressFX()
        .accessibilityLabel(Text(title + (isLocked ? " (locked)" : "")))
    }
}

// MARK: - Locked/sunken appearance (still tappable)

private struct TileAvailability: ViewModifier {
    let isEnabled: Bool
    
    func body(content: Content) -> some View {
        content
            .saturation(isEnabled ? 1.0 : 0.05)
            .opacity(isEnabled ? 1.0 : 0.6)
    }
}
private extension View {
    /// Makes a tile look sunken/locked but **keeps it tappable**.
    func tileAvailability(isEnabled: Bool) -> some View {
        modifier(TileAvailability(isEnabled: isEnabled))
    }
}

// MARK: - Press feedback

private struct PressFX: ViewModifier {
    @GestureState private var pressed = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.98 : 1.0)
            .opacity(pressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: pressed)
            .gesture(DragGesture(minimumDistance: 0).updating($pressed) { _, st, _ in st = true })
    }
}
private extension View { func pressFX() -> some View { modifier(PressFX()) } }

private struct PressEffect: ViewModifier { // alias for your previous helpers
    @GestureState private var pressed = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.98 : 1.0)
            .opacity(pressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: pressed)
            .gesture(DragGesture(minimumDistance: 0).updating($pressed) { _, st, _ in st = true })
    }
}
private extension View { func scaleEffectOnPress() -> some View { modifier(PressEffect()) } }

// MARK: - Small helpers

private extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255
        let g = Double((hex >>  8) & 0xff) / 255
        let b = Double((hex >>  0) & 0xff) / 255
        self = Color(red: r, green: g, blue: b).opacity(alpha)
    }
}
