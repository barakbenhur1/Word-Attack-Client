//
//  PremiumHubView.swift
//

import SwiftUI
import Combine
import CoreHaptics
import CoreMotion
import Foundation

// MARK: - AI Difficulty
private func loadAIDifficulty() -> AIDifficulty? {
    // Do NOT default to easy. When no value -> AI OFF.
    guard let s = UserDefaults.standard.string(forKey: "aiDifficulty") else { return nil }
    switch s {
    case AIDifficulty.easy.rawValue.name:   return .easy
    case AIDifficulty.medium.rawValue.name: return .medium
    case AIDifficulty.hard.rawValue.name:   return .hard
    case AIDifficulty.boss.rawValue.name:   return .boss
    default: return nil
    }
}

/// Tiny bridge so GameView can mirror the Hub's main round timer.
final class HubTimerBridge: ObservableObject {
    @Published var secondsLeft: Int = 0
    @Published var total: Int = 0
    func set(_ s: Int, total t: Int) { secondsLeft = s; total = t }
}

// MARK: - Entry

public struct PremiumHubView: View {
    @EnvironmentObject private var timerBridge: HubTimerBridge
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    private var language: String? { local.locale.identifier.components(separatedBy: "_").first }
    private var email: String? { loginHandeler.model?.email }
    
    @StateObject private var hub: PremiumHubModel
    @State private var engine: CHHapticEngine? = try? CHHapticEngine()
    
    @State private var presentedSlot: MiniSlot?
    @State private var activeSlot: MiniSlot?
    @State private var didResolveSheet = false
    
    public init(email: String?) {
        _hub = StateObject(wrappedValue: PremiumHubModel(email: email))
    }
    
    public var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(hue: 0.64, saturation: 0.25, brightness: 0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Discover letters in tactile mini-games. Use them to solve the word.".localized)
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 8)
                    
                    Grid3x3(hub: hub, presentedSlot: $presentedSlot, engine: engine)
                        .disabled(hub.vm.word == .empty)
                    
                    if !hub.discoveredLetters.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Available letters".localized)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            DiscoveredBeltView(letters: Array(hub.discoveredLetters).sorted())
                        }
                        .padding(.top, 4)
                    } else {
                        Text("No letters yet".localized)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, 4)
                    }
                    
                    Button { lightTap(engine) } label: {
                        HStack {
                            Text("Find letters in mini-games".localized)
                            Spacer()
                            Image(systemName: language == "he" ? "arrow.left" : "arrow.right")
                        }
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .environmentObject(hub.vm)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 12) {
                BackPill {
                    PremiumCoplitionHandler.shared.onForceEndPremium = { _, _ in }
                    hub.stop()
                    router.navigateBack()
                }
                Spacer()
                SolvedCounterPill(count: hub.solvedWords,
                                  onTap: { router.navigateTo(.premiumScore) } )
                MainRoundTimerView(secondsLeft: hub.mainSecondsLeft,
                                   total: hub.mainRoundLength)
                .frame(maxWidth: min(UIScreen.main.bounds.width * 0.55, 360), minHeight: 18, maxHeight: 18)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .onChange(of: presentedSlot) { _, newValue in
            if let s = newValue { activeSlot = s; didResolveSheet = false }
        }
        .sheet(item: $presentedSlot, onDismiss: {
            if let s = activeSlot, !didResolveSheet { hub.replaceSlot(s) }
            activeSlot = nil
        }) { slot in
            MiniGameSheet(slot: slot, hub: hub) { result in
                func close() {
                    didResolveSheet = true
                    hub.replaceSlot(slot)
                    presentedSlot = nil
                }
                switch result {
                case .found(let ch):
                    hub.discoveredLetters.insert(ch)
                    hub.recordFoundLetter(ch) // ← track word-letter discovery time
                    success(engine)
                    if slot.kind != .aiMerchant { close() }
                case .foundMany(let chars):
                    for ch in chars {
                        hub.discoveredLetters.insert(ch)
                        hub.recordFoundLetter(ch) // ← track time for each
                    }
                    success(engine); close()
                case .nothing:
                    warn(engine); close()
                case .close:
                    close()
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
        }
        .onChange(of: hub.mainSecondsLeft) { old, new in
            timerBridge.set(new, total: hub.mainRoundLength)
            if old <= 0 && new == hub.mainRoundLength {
                presentedSlot = nil
            }
        }
        .onAppear {
            PremiumHubModel.configureFor(language: language)
            hub.refreshAIDifficulty()
            hub.start()
            timerBridge.set(hub.mainSecondsLeft, total: hub.mainRoundLength)
        }
        .onChange(of: local.locale) {
            PremiumHubModel.configureFor(language: language)
            hub.resetAll()
            timerBridge.set(hub.mainSecondsLeft, total: hub.mainRoundLength)
        }
    }
}

// MARK: - Top bar

private struct BackPill: View {
    var action: () -> Void
    var body: some View { BackButton(action: action).environment(\.colorScheme, .dark) }
}

// 🏆 Pill showing solved words count
private struct SolvedCounterPill: View {
    let count: Int
    let onTap: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill").font(.system(size: 12, weight: .bold))
            Text("\(count)").font(.caption.weight(.bold)).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        .accessibilityLabel("Solved words \(count)".localized)
        .onTapGesture { onTap() }
    }
}

// MARK: - Palette

enum PremiumPalette {
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.09)
    static let glow = Color.white.opacity(0.22)
    static let accent = Color.cyan
    static let accent2 = Color.mint
    static let frost = Color.white.opacity(0.85)
    static let sand = Color(hue: 0.10, saturation: 0.35, brightness: 0.90)
    static let wax = Color(hue: 0.10, saturation: 0.08, brightness: 0.95)
    static let sonar = Color(hue: 0.58, saturation: 0.85, brightness: 0.75)
}

// MARK: - Model

private enum MiniKind: CaseIterable {
    // legacy
    case sand, wax, fog, sonar, ripple, magnet, frost, gyro
    // new
    case aiMerchant, symbolPick, symbolPuzzle, luckyWait
    
    var title: String {
        switch self {
        case .sand: "Sand Dig".localized
        case .wax: "Wax Press".localized
        case .fog: "Fog Wipe".localized
        case .sonar: "Sonar".localized
        case .ripple: "Ripples".localized
        case .magnet: "Magnet".localized
        case .frost: "Frost".localized
        case .gyro: "Playing Tag".localized
        case .aiMerchant: "AI Merchant".localized
        case .symbolPick: "Spot the Letter".localized
        case .symbolPuzzle: "Symbol Puzzle".localized
        case .luckyWait: "Lucky Wait".localized
        }
    }
    
    var icon: String {
        switch self {
        case .sand: "hand.draw"
        case .wax: "hand.point.up.left"
        case .fog: "wind"
        case .sonar: "dot.radiowaves.left.and.right"
        case .ripple: "aqi.low"
        case .magnet: "paperclip.circle.fill"
        case .frost: "snowflake"
        case .gyro: "figure.run.circle.fill"
        case .aiMerchant: "brain.head.profile"
        case .symbolPick: "textformat.abc.dottedunderline"
        case .symbolPuzzle: "puzzlepiece.extension"
        case .luckyWait: "hourglass"
        }
    }
    
    var baseLetterChance: Double {
        switch self {
        case .fog:    return 0.22
        case .sand:   return 0.45
        case .wax:    return 0.45
        case .sonar:  return 0.66
        case .ripple: return 0.35
        case .magnet: return 0.40
        case .frost:  return 0.30
        case .gyro:   return 0.40
        case .aiMerchant: return 1.0
        case .symbolPick: return 1.0
        case .symbolPuzzle: return 1.0
        case .luckyWait: return 0.0
        }
    }
    
    static var legacyCases: [MiniKind] { [.sand, .wax, .fog, .sonar, .ripple, .magnet, .frost, .gyro] }
}

private struct MiniSlot: Identifiable, Hashable {
    let id = UUID()
    let kind: MiniKind
    let expiresAt: Date
    let containsLetter: Bool
    let seededLetter: Character?
    var secondsLeft: Int { max(0, Int(expiresAt.timeIntervalSinceNow.rounded())) }
}

private final class PremiumHubModel: ObservableObject {
    // 🔤 Alphabets (static, configured at runtime)
    private static let englishAlphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    // 22 Hebrew letters (no final forms)
    private static let hebrewAlphabet: [Character] = Array("אבגדהוזחטיכלמנסעפצקרשת")
    private static var currentAlphabet: [Character] = englishAlphabet
    
    private static let staticMainRoundLength = Int(60 * 6) // round length in minutes
    
    static func configureFor(language: String?) {
        currentAlphabet = (language == "he") ? hebrewAlphabet : englishAlphabet
    }
    static func randomLetter() -> Character { currentAlphabet.randomElement() ?? "A" }
    static func isLetter(_ ch: Character) -> Bool { currentAlphabet.contains(ch) }
    static func randomNonLetter() -> Character {
        let symbols = Array("!@#$%^&*()_-+=~[]{}<>/\\|:;,.?0123456789")
        return symbols.randomElement() ?? "#"
    }
    
    @Published private(set) var slots: [MiniSlot] = []
    @Published private(set) var mainSecondsLeft: Int = PremiumHubModel.staticMainRoundLength
    
    @Published var discoveredLetters: Set<Character> = []
    @Published var gameHistory: [[String]] = []
    @Published var canInteract: Bool = true
    @Published var aiDifficulty: AIDifficulty? = nil
    @Published var solvedWords: Int = 0
    
    /// last time a **current word** letter was discovered
    private var lastWordLetterFoundAt: Date = Date()
    
    let vm = PremiumHubViewModel()
    
    var mainRoundLength: Int { PremiumHubModel.staticMainRoundLength }
    private var windowSeconds: TimeInterval { Double(mainRoundLength) / 8.0 }
    
    private var tick: AnyCancellable?
    private let email: String?
    
    init(email: String?) {
        self.email = email
        self.aiDifficulty = loadAIDifficulty()
        self.resetLoop()
    }
    
    /// Refresh AI difficulty and purge any existing AI-Merchant slots if AI is disabled.
    func refreshAIDifficulty() {
        self.aiDifficulty = loadAIDifficulty()
        if aiDifficulty == nil {
            // Replace any existing AI Merchant slots immediately so chance is truly 0%.
            slots = slots.map { $0.kind == .aiMerchant ? self.makeSlot(hasAI: false) : $0 }
        }
    }
    
    func start() {
        if slots.isEmpty {
            slots = uniqueInitialSlots(hasAI: aiDifficulty != nil)    // ← unique on first fill
        } else if aiDifficulty == nil {
            // If AI turned off while running, purge AI tiles (refreshing those is fine to duplicate)
            slots = slots.map { $0.kind == .aiMerchant ? self.makeSlot(hasAI: false) : $0 }
        }
        
        guard tick == nil else { return }
        tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.mainSecondsLeft -= 1
                if self.mainSecondsLeft <= 0 {
                    Task(priority: .high) {
                        try? await Task.sleep(nanoseconds: 1_000_000)
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            resetAll()
                        }
                    }
                    return
                }
                // Allow duplicates on expiry refresh:
                self.slots = self.slots.map { s in
                    s.expiresAt <= Date() ? self.makeSlot(hasAI: self.aiDifficulty != nil) : s
                }
            }
    }
    
    private func resetLoop() {
        self.mainSecondsLeft = self.mainRoundLength
        self.discoveredLetters = []
        self.gameHistory = []
        self.lastWordLetterFoundAt = Date() // start window from "now"
        if let email {
            Task(priority: .userInitiated) {
                await vm.word(email: email)
                let solved = await vm.getScore(email: email)
                UserDefaults.standard.set(solved, forKey: "wins_count")
                await MainActor.run {
                    solvedWords = solved
                }
            }
        }
    }
    
    func resetAll() {
        slots = uniqueInitialSlots(hasAI: aiDifficulty != nil)   // ← unique on full reset
        resetLoop()
    }
    
    func stop() { tick?.cancel(); tick = nil }
    
    func slot(atVisualIndex r: Int, _ c: Int) -> MiniSlot? {
        let map = [[0,1,2],[3,-1,4],[5,6,7]]
        let i = map[r][c]
        guard i >= 0, i < slots.count else { return nil }
        return slots[i]
    }
    
    func replaceSlot(_ s: MiniSlot) {
        guard let i = slots.firstIndex(of: s) else { return }
        slots[i] = self.makeSlot(hasAI: aiDifficulty != nil)
    }
    
    // Create a slot for a specific kind (used for unique initial grid)
    private func makeSlot(kind: MiniKind) -> MiniSlot {
        let contains: Bool
        let seed: Character?
        let ttl: Int
        
        switch kind {
        case .aiMerchant:
            contains = true; seed = nil; ttl = 20
        case .symbolPick:
            contains = true; seed = nil; ttl = 15
        case .symbolPuzzle:
            contains = false; seed = nil; ttl = 30   // “unknown” in header; mini decides
        case .luckyWait:
            contains = false; seed = nil; ttl = 12
        case .gyro:
            contains = true; seed = pickLetterForOffer() // always letter for gyro
            let pace: Double = 12
            ttl = max(12, Int(pace * 2.2))
        default:
            contains = Double.random(in: 0...1) < kind.baseLetterChance
            seed = contains ? pickLetterForOffer() : nil
            let pace: Double
            switch kind {
            case .fog: pace = 6
            case .sand, .wax: pace = 14
            case .sonar: pace = 20
            default: pace = 12
            }
            ttl = max(12, Int(pace * 2.2))
        }
        
        return MiniSlot(kind: kind,
                        expiresAt: Date().addingTimeInterval(TimeInterval(ttl)),
                        containsLetter: contains,
                        seededLetter: seed)
    }
    
    // Build the initial 8 slots with no duplicate kinds
    private func uniqueInitialSlots(hasAI: Bool) -> [MiniSlot] {
        var available = MiniKind.allCases
        if !hasAI {
            available.removeAll { $0 == .aiMerchant } // enforce 0% AI when disabled
        }
        let chosen = Array(available.shuffled().prefix(8))
        return chosen.map { makeSlot(kind: $0) }
    }
    
    private static func selectKind(hasAI: Bool) -> MiniKind {
        // Requested appearance rates
        var weights: [(MiniKind, Double)] = [
            (.sand, 11), (.wax, 11), (.fog, 11), (.sonar, 11), (.ripple, 11),
            (.magnet, 10), (.frost, 9), (.gyro, 8),
            (.aiMerchant, 3),
            (.symbolPick, 5), (.symbolPuzzle, 5), (.luckyWait, 5)
        ]
        if !hasAI {
            weights.removeAll { $0.0 == .aiMerchant }
        }
        let total = weights.reduce(0) { $0 + $1.1 }
        let r = Double.random(in: 0..<total)
        var acc = 0.0
        for (kind, w) in weights {
            acc += w
            if r < acc { return kind }
        }
        return weights.last?.0 ?? .sand
    }
    
    // MARK: Preference & picking
    
    /// letters from alphabet that are not discovered yet
    private func undiscoveredAlphabetLetters() -> [Character] {
        let all = Set(Self.currentAlphabet)
        return Array(all.subtracting(discoveredLetters))
    }
    
    /// undiscovered letters that belong to the current word
    private func remainingWordLetters() -> [Character] {
        let wordUpper = vm.wordValue.uppercased()
        let wordSet = Set(wordUpper.filter { Self.isLetter($0) })
        let missing = wordSet.subtracting(discoveredLetters)
        return Array(missing)
    }
    
    /// true when we should prefer giving a current-word letter next
    private func shouldPreferWordLetter() -> Bool {
        guard !vm.wordValue.isEmpty else { return false }
        let missing = remainingWordLetters()
        guard !missing.isEmpty else { return false }
        return Date().timeIntervalSince(lastWordLetterFoundAt) >= windowSeconds
    }
    
    /// pick a single letter to seed/offer, honoring preference rule
    func pickLetterForOffer() -> Character {
        let preferWord = shouldPreferWordLetter()
        let pool = preferWord ? remainingWordLetters() : undiscoveredAlphabetLetters()
        if let choice = pool.randomElement() { return choice }
        let alt = preferWord ? undiscoveredAlphabetLetters() : remainingWordLetters()
        if let choice = alt.randomElement() { return choice }
        return Self.randomLetter()
    }
    
    /// pick several unique letters to offer (best effort uniqueness)
    func pickLettersForOffer(count: Int) -> [Character] {
        var set = Set<Character>()
        while set.count < count {
            set.insert(pickLetterForOffer())
            if set.count < count && set.count >= Self.currentAlphabet.count {
                break
            }
        }
        return Array(set)
    }
    
    /// record letter discovery time if it's in the current word
    func recordFoundLetter(_ ch: Character) {
        let wordU = vm.wordValue.uppercased()
        if wordU.contains(String(ch).uppercased()) {
            lastWordLetterFoundAt = Date()
        }
    }
    
    // MARK: Slot creation (instance, so it can consult state)
    private func makeSlot(hasAI: Bool) -> MiniSlot {
        let kind = Self.selectKind(hasAI: hasAI)
        let contains: Bool
        let seed: Character?
        let ttl: Int
        
        switch kind {
        case .aiMerchant:
            contains = true; seed = nil; ttl = 20
        case .symbolPick:
            contains = true; seed = nil; ttl = 15
        case .symbolPuzzle:
            contains = false; seed = nil; ttl = 30     // keep header honest
        case .luckyWait:
            contains = false; seed = nil; ttl = 12
        case .gyro:
            contains = true
            seed = pickLetterForOffer()                // always letter for gyro
            let pace: Double = 12
            ttl = max(12, Int(pace * 2.2))
        default:
            contains = Double.random(in: 0...1) < kind.baseLetterChance
            seed = contains ? pickLetterForOffer() : nil
            let pace: Double
            switch kind {
            case .fog: pace = 6
            case .sand, .wax: pace = 14
            case .sonar: pace = 20
            default: pace = 12
            }
            ttl = max(12, Int(pace * 2.2))
        }
        
        return MiniSlot(kind: kind,
                        expiresAt: Date().addingTimeInterval(TimeInterval(ttl)),
                        containsLetter: contains,
                        seededLetter: seed)
    }
}

// MARK: - Grid 3×3

private struct Grid3x3: View {
    @ObservedObject var hub: PremiumHubModel
    @Binding var presentedSlot: MiniSlot?
    let engine: CHHapticEngine?
    private let spacing: CGFloat = 16
    
    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let gridW = max(1, totalW - 2*18)
            let cell = max(64, floor((gridW - 2*spacing) / 3))
            VStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { c in
                            if r == 1 && c == 1 {
                                MainRoundCircle(hub: hub)
                                    .frame(width: cell * 0.72, height: cell * 0.72)
                                    .frame(width: cell, height: cell)
                            } else if let slot = hub.slot(atVisualIndex: r, c) {
                                MiniGameSlotView(slot: slot, ai: hub.aiDifficulty)
                                    .frame(width: cell, height: cell)
                                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .onTapGesture {
                                        guard hub.canInteract else { return }
                                        // Block AI sheet if AI is OFF; replace tile instead.
                                        if slot.kind == .aiMerchant, hub.aiDifficulty == nil {
                                            hub.replaceSlot(slot)
                                            return
                                        }
                                        presentedSlot = slot
                                        lightTap(engine)
                                    }
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 3 * 120)
    }
}

// MARK: - Gold gradient (strong contrast)
extension LinearGradient {
    static let ready = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 1.0, green: 0.95, blue: 0.70),
            Color(red: 1.0, green: 0.84, blue: 0.0),
            Color(red: 0.80, green: 0.50, blue: 0.0),
            Color(red: 0.55, green: 0.35, blue: 0.05),
            Color(red: 1.0, green: 0.95, blue: 0.70)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let notReady = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 0.90, green: 0.92, blue: 0.95),
            Color(red: 0.66, green: 0.71, blue: 0.76),
            Color(red: 0.42, green: 0.47, blue: 0.52),
            Color(red: 0.22, green: 0.26, blue: 0.31),
            Color(red: 0.90, green: 0.92, blue: 0.95)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
}

// MARK: - Pressed bounce style (cute spring)
struct PressedBounceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .shadow(radius: configuration.isPressed ? 6 : 12, y: configuration.isPressed ? 4 : 8)
            .animation(.spring(response: 0.22, dampingFraction: 0.65, blendDuration: 0.1),
                       value: configuration.isPressed)
    }
}

// MARK: - Shimmer sweep overlay
private struct ShimmerSweep: View {
    @Binding var trigger: Bool
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Rectangle()
                .fill(
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: .white.opacity(0.0), location: 0.00),
                        .init(color: .white.opacity(0.10), location: 0.45),
                        .init(color: .white.opacity(0.45), location: 0.50),
                        .init(color: .white.opacity(0.10), location: 0.55),
                        .init(color: .white.opacity(0.00), location: 1.00),
                    ]), startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: w * 0.45)
                .rotationEffect(.degrees(30))
                .offset(x: trigger ? w*1.1 : -w*1.1)
                .animation(.easeOut(duration: 0.06), value: trigger)
        }
        .allowsHitTesting(false)
        .blendMode(.plusLighter)
        .clipShape(Circle())
    }
}

// MARK: - Ripple ring overlay
private struct RippleRing: View {
    @Binding var fire: Bool
    var body: some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.65), lineWidth: 2)
            .scaleEffect(fire ? 1.45 : 0.9)
            .opacity(fire ? 0.0 : 0.8)
            .animation(.easeOut(duration: 0.06), value: fire)
            .allowsHitTesting(false)
    }
}

// MARK: - Main
private struct MainRoundCircle: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var vm: PremiumHubViewModel
    @ObservedObject var hub: PremiumHubModel
    
    @State private var shimmer = false
    @State private var ripple  = false
    
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            shimmer = true
            ripple = true
            Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 60_000_000)
                shimmer = false
                ripple = false
                try? await Task.sleep(nanoseconds: 30_000_000)
                await MainActor.run {
                    router.navigateTo(.premiumGame(
                        word: vm.wordValue,
                        history: hub.gameHistory,
                        allowedLetters: String(hub.discoveredLetters).lowercased()
                    ))
                }
            }
        } label: {
            ZStack {
                let word = vm.wordValue
                let isReady = !word.isEmpty && word.lettersAreSubset(of: hub.discoveredLetters)
                Circle()
                    .fill(isReady ? LinearGradient.ready : LinearGradient.notReady)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                            .blur(radius: 0.4)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
                    .shadow(color: isReady ? Color.yellow.opacity(0.45) : Color.gray.opacity(0.45), radius: 16, x: 0, y: 10)
                    .overlay(ShimmerSweep(trigger: $shimmer))
                    .overlay(RippleRing(fire: $ripple).padding(6))
                
                VStack(spacing: 10) {
                    AppTitle()
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        .scaleEffect(.init(width: 0.72, height: 0.72))
                        .padding(.all, -8)
                    
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { i in
                            let show = i < min(5, hub.discoveredLetters.count)
                            Circle()
                                .fill(show ? .white : .white.opacity(0.25))
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 0.6))
                                .shadow(color: show ? .white.opacity(0.8) : .clear, radius: 2, y: 1)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .padding(12)
            }
        }
        .buttonStyle(PressedBounceStyle())
        .tint(.black)
        .onAppear {
            PremiumCoplitionHandler.shared.onForceEndPremium = { history, reset in
                if reset { hub.resetAll() }
                else if let history { hub.gameHistory = history }
            }
        }
    }
}


// MARK: - Tile

private struct MiniGameSlotView: View {
    let slot: MiniSlot
    var ai: AIDifficulty?
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if slot.kind == .aiMerchant, ai != nil {
                    Circle().stroke(
                        LinearGradient(colors: [.white.opacity(0.9), PremiumPalette.accent],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2.5
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: PremiumPalette.glow, radius: 6, y: 3)
                }
                Image(systemName: slot.kind.icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(height: 30)
            }
            Text(slot.kind.title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let secs = max(0, Int(slot.expiresAt.timeIntervalSince(timeline.date).rounded()))
                Text("refresh in \(secs)s".localized)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PremiumPalette.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PremiumPalette.stroke, lineWidth: 1))
        )
    }
}

// MARK: - Popup host

private enum MiniResult { case found(Character), foundMany([Character]), nothing, close }

private struct MiniGameSheet: View {
    let slot: MiniSlot
    @ObservedObject var hub: PremiumHubModel
    var onDone: (MiniResult) -> Void
    @State private var closed = false
    
    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(.secondary.opacity(0.35)).frame(width: 38, height: 5).padding(.top, 8)
            HStack {
                Label(slot.kind.title, systemImage: slot.kind.icon)
                    .labelStyle(.titleAndIcon)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Spacer()
                if slot.containsLetter {
                    Text("Contains letter".localized)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(PremiumPalette.accent.opacity(0.22)))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Text("May be empty".localized)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal)
            
            Group {
                switch slot.kind {
                case .sand:         SandDigMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .wax:          WaxPressMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .fog:          FogWipeMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .sonar:        SonarMini(hasLetter: slot.containsLetter, seed: slot.seededLetter, onDone: onDone)
                case .ripple:       RippleMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .magnet:       MagnetMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .frost:        FrostMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .gyro:         GyroMazeMini(hasLetter: slot.containsLetter, seed: slot.seededLetter, onDone: onDone)
                case .aiMerchant:   AIMerchantMini(deadline: slot.expiresAt, ai: hub.aiDifficulty, hub: hub, onDone: onDone)
                case .symbolPick:   SymbolPickMini(deadline: slot.expiresAt, hub: hub, onDone: onDone)
                case .symbolPuzzle: SymbolPuzzleMini(deadline: slot.expiresAt, hub: hub, onDone: onDone)
                case .luckyWait:    LuckyWaitMini(deadline: slot.expiresAt, hub: hub, onDone: onDone)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 14)
        }
        .background(
            LinearGradient(colors: [Color.black.opacity(0.88), Color.black.opacity(0.94)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
        .onChange(of: hub.mainSecondsLeft) { old, new in
            if old <= 0 && new == hub.mainRoundLength {
                guard !closed else { return }
                closed = true
                onDone(.nothing)
            }
        }
        // global auto-close on expiry
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            guard !closed else { return }
            if Date() >= slot.expiresAt {
                closed = true
                onDone(.nothing)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - Shared small views

private struct DiscoveredBeltView: View {
    let letters: [Character]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(letters, id: \.self) { ch in
                    Text(String(ch))
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(PremiumPalette.accent))
                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                        .shadow(radius: 3, y: 2)
                }
            }
        }
    }
}

// MARK: - Timer strip

struct MainRoundTimerView: View {
    let secondsLeft: Int
    let total: Int
    
    @State private var pulse = false
    @State private var flashOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var progress: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(secondsLeft) / Double(total)))
    }
    
    private enum Phase { case high, mid, low }
    private var phase: Phase {
        switch progress {
        case 0.66...1.0: return .high
        case 0.33..<0.66: return .mid
        default: return .low
        }
    }
    
    private var isCritical: Bool { secondsLeft <= 30 }
    private var isFinal:    Bool { secondsLeft <= 10 }
    
    private var barGradient: LinearGradient {
        // high: cyan→mint, mid: amber, low: red
        let colors: [Color]
        switch phase {
        case .high:
            colors = [PremiumPalette.accent, PremiumPalette.accent2]
        case .mid:
            colors = [Color(hue: 0.12, saturation: 0.95, brightness: 1.0), .orange]
        case .low:
            colors = [.red, Color(hue: 0.0, saturation: 0.75, brightness: 0.9)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * progress
            ZStack(alignment: .leading) {
                // track
                Capsule().fill(Color.white.opacity(0.15))
                
                // fill
                Capsule()
                    .fill(barGradient)
                    .frame(width: w)
                // urgent heartbeat (vertical breathe) + hue tick under 30s
                    .scaleEffect(x: 1,
                                 y: (isCritical && !reduceMotion && pulse) ? 1.06 : 1,
                                 anchor: .center)
                    .hueRotation(.degrees(isCritical && !reduceMotion && pulse ? 5 : 0))
                // warm glow that intensifies as time runs out
                    .shadow(color: isCritical
                            ? .red.opacity(pulse ? 0.55 : 0.30)
                            : .clear,
                            radius: isCritical ? (isFinal ? 14 : 10) : 0,
                            x: 0, y: isCritical ? 6 : 0)
                    .animation(.easeInOut(duration: 0.25), value: pulse)
                    .animation(.easeInOut(duration: 0.25), value: progress)
                    .animation(.easeInOut(duration: 0.25), value: phase)
                
                // brief tick flash on the bar edge for last 10s
                if isCritical {
                    Capsule()
                        .stroke(Color.white.opacity(flashOpacity), lineWidth: 3)
                        .frame(width: w)
                        .blendMode(.plusLighter)
                }
            }
        }
        // readout
        .overlay(
            HStack(spacing: 6) {
                Text("\(secondsLeft)s".localized)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isCritical ? .white : .white.opacity(0.9))
                    .scaleEffect(isFinal && !reduceMotion && pulse ? 1.06 : 1.0)
                    .animation(.easeOut(duration: 0.18), value: pulse)
                Text("round".localized)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
                .padding(.horizontal, 6),
            alignment: .trailing
        )
        .clipShape(Capsule())
        .frame(height: 18)
        .task(id: isCritical) {
            guard isCritical, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.22)) { pulse.toggle() }
            flashOpacity = isFinal ? 0.9 : 0.5
            withAnimation(.easeOut(duration: 0.16)) { flashOpacity = 0 }
        }
        // drive urgency by second ticks (no shake)
        .onChange(of: secondsLeft) { _, _ in
            guard isCritical else { return }
            withAnimation(.easeInOut(duration: 0.22)) { pulse.toggle() }
            
            // tiny flash on the stroke for last 30s
            flashOpacity = isFinal ? 0.9 : 0.5
            withAnimation(.easeOut(duration: 0.16)) { flashOpacity = 0 }
        }
    }
}


// MARK: - Legacy Minis (unchanged behavior but seeded via rule)

private struct SandDigMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void
    
    @State private var strokes: [CGPoint] = []
    @State private var hit = false
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(PremiumPalette.sand)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .position(letterPos)
                        .mask(RevealMask(points: strokes))
                        .animation(.easeInOut(duration: 0.2), value: strokes.count)
                }
                Canvas { ctx, _ in
                    for p in strokes {
                        let rect = CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)
                        ctx.fill(Ellipse().path(in: rect), with: .color(.white.opacity(0.08)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    strokes.append(g.location)
                    if hasLetter && !hit {
                        let d = hypot(g.location.x - letterPos.x, g.location.y - letterPos.y)
                        if d < 40 { hit = true }
                    }
                }
                .onEnded { _ in
                    onDone(hasLetter && hit ? .found(seeded) : .nothing)
                })
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 60
                letterPos = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                    y: .random(in: inset...(geo.size.height - inset)))
            }
        }
        .frame(height: 300)
    }
}

private struct RevealMask: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for pt in points { p.addEllipse(in: CGRect(x: pt.x-28, y: pt.y-28, width: 56, height: 56)) }
        return p
    }
}

private struct WaxPressMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void
    
    @State private var pressPoint: CGPoint?
    @State private var clarity: CGFloat = 0
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"
    
    // finger feedback
    @State private var ringPulse = false
    
    var body: some View {
        GeometryReader { geo in
            let shape  = RoundedRectangle(cornerRadius: 18, style: .continuous)
            let bounds = CGRect(origin: .zero, size: geo.size)
            
            ZStack {
                // base
                shape
                    .fill(PremiumPalette.wax)
                    .overlay(
                        // wax sheen that clears as you press
                        LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(shape)
                        .opacity(0.7 - 0.6 * clarity)
                    )
                    .overlay(shape.stroke(PremiumPalette.stroke, lineWidth: 1))
                
                // letter (revealed by the press mask)
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.42,
                                      weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.9))
                        .position(letterPos)
                        .mask(
                            Group {
                                if let p = pressPoint {
                                    Circle()
                                        .size(CGSize(width: 40 + 40 * clarity, height: 40 + 40 * clarity))
                                        .offset(x: p.x - (20 + 70 * clarity),
                                                y: p.y - (20 + 70 * clarity))
                                }
                            }
                        )
                        .animation(.easeInOut(duration: 0.15), value: clarity)
                }
                
                // ===== Finger-move visual feedback (clipped to shape) =====
                if let p = pressPoint {
                    // soft warm glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    .white.opacity(0.28 * (0.4 + clarity * 0.6)),
                                    .white.opacity(0.02)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 40 + 120 * clarity
                            )
                        )
                        .frame(width: 80 + 220 * clarity, height: 80 + 220 * clarity)
                        .position(p)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                    
                    // subtle ring pulse
                    Circle()
                        .stroke(.white.opacity(0.45), lineWidth: 2)
                        .frame(width: 38 + 100 * clarity, height: 38 + 100 * clarity)
                        .position(p)
                        .scaleEffect(ringPulse ? 1.06 : 0.96)
                        .opacity(0.9)
                        .shadow(color: .white.opacity(0.22), radius: 3, y: 1)
                        .animation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true),
                                   value: ringPulse)
                        .onAppear { ringPulse = true }
                        .onDisappear { ringPulse = false }
                        .allowsHitTesting(false)
                }
            }
            // clip everything to the rounded rect & use it as hit area
            .clipShape(shape)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        // only react if finger is inside the shape
                        let inside = shape.path(in: bounds).contains(g.location)
                        if inside {
                            pressPoint = g.location
                            clarity = min(1, clarity + 0.02)
                        } else {
                            // outside → hide feedback, do not increase clarity
                            pressPoint = nil
                        }
                    }
                    .onEnded { _ in
                        let success = hasLetter &&
                        overlap(pressPoint ?? .zero, letterPos, clarity: clarity)
                        onDone(success ? .found(seeded) : .nothing)
                        pressPoint = nil
                        clarity = 0
                    }
            )
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                letterPos = CGPoint(
                    x: .random(in: inset...(geo.size.width - inset)),
                    y: .random(in: inset...(geo.size.height - inset))
                )
            }
        }
        .frame(height: 300)
    }
    
    private func overlap(_ a: CGPoint, _ b: CGPoint, clarity: CGFloat) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 80 * max(0.4, clarity)
    }
}



private struct FogWipeMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void
    @State private var strokes: [CGPoint] = []
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"
    @State private var finished = false
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(PremiumPalette.accent)
                        .position(letterPos)
                        .mask(RevealMask(points: strokes))
                }
                RoundedRectangle(cornerRadius: 18)
                    .fill(PremiumPalette.frost)
                    .mask(
                        Rectangle().compositingGroup()
                            .luminanceToAlpha()
                            .overlay(
                                Canvas { ctx, _ in
                                    ctx.addFilter(.alphaThreshold(min: 0.01))
                                    ctx.addFilter(.blur(radius: 6))
                                    for p in strokes {
                                        let rect = CGRect(x: p.x - 24, y: p.y - 24, width: 48, height: 48)
                                        ctx.fill(Ellipse().path(in: rect), with: .color(.black))
                                    }
                                }
                            )
                    )
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in guard !finished else { return }; strokes.append(g.location) }
                    .onEnded { _ in
                        guard !finished else { return }; finished = true
                        let success = hasLetter && strokes.contains { hypot($0.x - letterPos.x, $0.y - letterPos.y) < 40 }
                        onDone(success ? .found(seeded) : .nothing)
                    }
            )
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                letterPos = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                    y: .random(in: inset...(geo.size.height - inset)))
            }
        }
        .frame(height: 260)
    }
}

private struct SonarMini: View {
    let hasLetter: Bool
    let seed: Character?                // stable seed from slot
    let onDone: (MiniResult) -> Void
    
    @State private var target: CGPoint = .zero
    @State private var pings: [Ping] = []
    @State private var solved = false
    @State private var letterToShow: Character? = nil   // ← frozen once
    struct Ping: Identifiable { let id = UUID(); let center: CGPoint; let date: Date; let strength: Double }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                
                GridPattern().stroke(Color.white.opacity(0.15), lineWidth: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                
                TimelineView(.animation) { timeline in
                    Canvas { ctx, _ in
                        for ping in pings {
                            let t = timeline.date.timeIntervalSince(ping.date)
                            let r = CGFloat(20 + t * 180)
                            let alpha = max(0, 1.0 - t / 1.6)
                            let rect = CGRect(x: ping.center.x - r/2, y: ping.center.y - r/2, width: r, height: r)
                            let color = PremiumPalette.sonar.opacity(alpha * (0.4 + 0.6 * ping.strength))
                            ctx.stroke(Circle().path(in: rect), with: .color(color), lineWidth: 2)
                        }
                    }
                }
                
                if solved, let ch = letterToShow {
                    Text(String(ch))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .position(target)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .gesture(DragGesture(minimumDistance: 0).onEnded { g in
                let p = g.location
                let d = max(1, hypot(p.x - target.x, p.y - target.y))
                let norm = max(0, 1 - Double(min(d, 220) / 220))
                pings.append(Ping(center: p, date: Date(), strength: norm))
                if d < 36 {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { solved = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        if let ch = letterToShow { onDone(.found(ch)) } else { onDone(.nothing) }
                    }
                }
            })
            .onAppear {
                letterToShow = hasLetter ? seed : nil  // freeze once
                let inset: CGFloat = 70
                target = CGPoint(
                    x: .random(in: inset...(geo.size.width - inset)),
                    y: .random(in: inset...(geo.size.height - inset))
                )
            }
        }
        .frame(height: 300)
    }
}

private struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for x in stride(from: rect.minX, through: rect.maxX, by: 24) {
            p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for y in stride(from: rect.minY, through: rect.maxY, by: 24) {
            p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}

private struct RippleMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void
    struct Ring: Identifiable { let id = UUID(); let center: CGPoint; let start: Date }
    @State private var rings: [Ring] = []
    @State private var target: CGPoint = .zero
    @State private var seeded: Character = "A"
    @State private var solved = false
    @State private var frameTimer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                if solved, hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .position(target)
                }
                TimelineView(.animation) { tl in
                    Canvas { ctx, _ in
                        for ring in rings {
                            let t = tl.date.timeIntervalSince(ring.start)
                            let r = CGFloat(10 + t * 150)
                            let alpha = max(0, 1.0 - t / 1.4)
                            let rect = CGRect(x: ring.center.x - r/2, y: ring.center.y - r/2, width: r, height: r)
                            ctx.stroke(Circle().path(in: rect), with: .color(.white.opacity(alpha)), lineWidth: 2)
                        }
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onTapGesture { p in rings.append(Ring(center: p, start: Date())) }
            .onReceive(frameTimer) { now in
                rings.removeAll { now.timeIntervalSince($0.start) > 1.6 }
                guard hasLetter, !solved else { return }
                for ring in rings {
                    let t = now.timeIntervalSince(ring.start)
                    let r = CGFloat(10 + t * 150)
                    if abs(r - hypot(ring.center.x - target.x, ring.center.y - target.y)) < 14 {
                        solved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onDone(.found(seeded)) }
                        break
                    }
                }
            }
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                target = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                 y: .random(in: inset...(geo.size.height - inset)))
            }
        }
        .frame(height: 280)
    }
}

private struct MagnetMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void

    struct Particle: Identifiable { let id = UUID(); var p: CGPoint; var v: CGVector }

    @State private var filings: [Particle] = []
    @State private var magnetPos: CGPoint = .zero
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"

    @State private var closeTicks = 0
    @State private var physicsTimer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()

    // Reveal state
    @State private var discovered = false
    @State private var captureAt: Date? = nil
    @State private var letterScale: CGFloat = 0.92
    @State private var letterOpacity: Double = 0.04   // faint by default

    var body: some View {
        GeometryReader { geo in
            let bounds = geo.size
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))

                // Rails (purely decorative)
                Canvas { ctx, _ in
                    var path = Path()
                    for _ in 0..<7 {
                        let w = Double.random(in: 60...90)
                        let h = Double.random(in: 10...16)
                        let x = Double.random(in: 20...(bounds.width-80))
                        let y = Double.random(in: 20...(bounds.height-20))
                        path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h),
                                            cornerSize: CGSize(width: 7, height: 7))
                    }
                    ctx.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 5)
                }

                // Letter (faint → bright when discovered)
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(bounds.width, bounds.height) * 0.42,
                                      weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(letterOpacity))
                        .scaleEffect(letterScale)
                        .position(letterPos)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: letterScale)
                        .animation(.easeInOut(duration: 0.18), value: letterOpacity)
                }

                // Metal filings
                Canvas { ctx, _ in
                    for f in filings {
                        let rect = CGRect(x: f.p.x - 2, y: f.p.y - 2, width: 4, height: 4)
                        ctx.fill(Ellipse().path(in: rect), with: .color(.white.opacity(0.8)))
                    }
                }

                // Magnet (user)
                Image(systemName: "paperclip.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(PremiumPalette.accent)
                    .position(magnetPos)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in guard !discovered else { return }; magnetPos = g.location }
                        .onEnded { _ in
                            guard !discovered else { return }
                            let d = hypot(magnetPos.x - letterPos.x, magnetPos.y - letterPos.y)
                            if hasLetter && d < 46 { triggerReveal() }
                            else { onDone(.nothing) }
                        })

                // Ripple burst when revealed
                TimelineView(.animation) { tl in
                    if let start = captureAt {
                        let dt = tl.date.timeIntervalSince(start)
                        Canvas { ctx, _ in
                            let c = letterPos
                            for i in 0..<3 {
                                let t = dt - Double(i) * 0.06
                                guard t >= 0, t <= 0.6 else { continue }
                                let p = t / 0.6
                                let r = CGFloat(12 + p * 130)
                                let a = 1.0 - p
                                let rect = CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2)
                                ctx.stroke(Circle().path(in: rect),
                                           with: .color(.white.opacity(0.35 * a)),
                                           lineWidth: 2)
                            }
                        }
                    }
                }
            }
            .onReceive(physicsTimer) { _ in
                guard !discovered else { return }

                // Update filings with magnet pull
                var updated: [Particle] = []
                for var f in filings {
                    let dx = magnetPos.x - f.p.x, dy = magnetPos.y - f.p.y
                    let d = max(16, hypot(dx, dy))
                    let pull: CGFloat = 1400 / (d*d)
                    f.v.dx += dx / d * pull
                    f.v.dy += dy / d * pull
                    f.v.dx *= 0.92; f.v.dy *= 0.92
                    f.p.x += f.v.dx; f.p.y += f.v.dy
                    updated.append(f)
                }
                filings = updated

                // Proximity dwell → reveal
                if hasLetter {
                    let d = hypot(magnetPos.x - letterPos.x, magnetPos.y - letterPos.y)
                    closeTicks = d < 48 ? (closeTicks + 1) : 0
                    if closeTicks > 15 { triggerReveal() }  // ~0.25s at 60fps
                }
            }
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                letterPos = CGPoint(x: .random(in: inset...(bounds.width - inset)),
                                    y: .random(in: inset...(bounds.height - inset)))
                magnetPos = CGPoint(x: bounds.width/2, y: 28)
                filings = (0..<90).map { _ in
                    Particle(p: CGPoint(x: .random(in: 20...(bounds.width-20)),
                                        y: .random(in: 20...(bounds.height-20))),
                             v: CGVector(dx: 0, dy: 0))
                }
            }
        }
        .frame(height: 300)
    }

    // MARK: - Reveal & close after animation
    private func triggerReveal() {
        guard !discovered else { return }
        discovered = true
        captureAt = Date()

        // pop + brighten letter
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            letterScale = 1.10
            letterOpacity = 1.0
        }
        // settle a bit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                letterScale = 1.00
            }
        }
        // close after users see it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            onDone(.found(seeded))
        }
    }
}

private struct FrostMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void
    
    @State private var heatPoints: [CGPoint] = []
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"
    
    // finger feedback
    @State private var touchPoint: CGPoint?
    @State private var heatLevel: CGFloat = 0
    @State private var ringPulse = false
    
    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            let bounds = CGRect(origin: .zero, size: geo.size)
            
            ZStack {
                // background + stroke
                shape
                    .fill(Color.black.opacity(0.88))
                    .overlay(shape.stroke(PremiumPalette.stroke, lineWidth: 1))
                
                // letter reveal
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.42,
                                      weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .position(letterPos)
                        .mask(HeatMask(points: heatPoints))
                }
                
                // frost texture
                FrostOverlay()
                    .opacity(0.9)
                
                // ===== Finger-move visual feedback (clipped by shape) =====
                if let p = touchPoint {
                    // warm glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    .white.opacity(0.28 * (0.4 + heatLevel * 0.6)),
                                    .white.opacity(0.02)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 40 + 120 * heatLevel
                            )
                        )
                        .frame(width: 80 + 220 * heatLevel, height: 80 + 220 * heatLevel)
                        .position(p)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                    
                    // breathing ring
                    Circle()
                        .stroke(.white.opacity(0.45), lineWidth: 2)
                        .frame(width: 38 + 40 * heatLevel, height: 38 + 40 * heatLevel)
                        .position(p)
                        .scaleEffect(ringPulse ? 1.06 : 0.96)
                        .opacity(0.9)
                        .shadow(color: .white.opacity(0.22), radius: 3, y: 1)
                        .animation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true),
                                   value: ringPulse)
                        .onAppear { ringPulse = true }
                        .onDisappear { ringPulse = false }
                        .allowsHitTesting(false)
                }
            }
            // ensure NOTHING renders outside the rounded rect
            .clipShape(shape)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let inside = shape.path(in: bounds).contains(g.location)
                        if inside {
                            touchPoint = g.location
                            heatPoints.append(g.location)
                            heatLevel = min(1, heatLevel + 0.04)
                        } else {
                            // outside → hide the indicators and do not add heat
                            touchPoint = nil
                        }
                    }
                    .onEnded { _ in
                        let success = hasLetter &&
                        heatPoints.contains { hypot($0.x - letterPos.x, $0.y - letterPos.y) < 42 }
                        onDone(success ? .found(seeded) : .nothing)
                        touchPoint = nil
                        heatLevel = 0
                    }
            )
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                letterPos = CGPoint(
                    x: .random(in: inset...(geo.size.width - inset)),
                    y: .random(in: inset...(geo.size.height - inset))
                )
            }
        }
        .frame(height: 280)
    }
}


private struct HeatMask: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for pt in points { p.addEllipse(in: CGRect(x: pt.x-28, y: pt.y-28, width: 56, height: 56)) }
        return p
    }
}
private struct FrostOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            for _ in 0..<200 {
                let r = CGFloat.random(in: 1...2.6)
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                ctx.fill(Ellipse().path(in: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(.white.opacity(0.6)))
            }
        }.blur(radius: 1.2)
    }
}

private struct GyroMazeMini: View {
    let hasLetter: Bool
    let seed: Character?
    let onDone: (MiniResult) -> Void

    // Frozen once on appear (parity with Sonar)
    @State private var letterChar: Character? = nil

    // Entities
    @State private var ball = CGPoint(x: 40, y: 40)
    @State private var target = CGPoint(x: 260, y: 220)
    @State private var velBall = CGVector(dx: 0, dy: 0)
    @State private var velTarget = CGVector(dx: 1.6, dy: -1.2)

    // UX & capture
    @State private var solved = false
    @State private var captureAt: Date? = nil
    @State private var letterScale: CGFloat = 1.0
    @State private var letterOpacity: Double = 1.0
    @State private var ballScale: CGFloat = 1.0

    // Idle & smoothing
    @State private var lastBallPos = CGPoint(x: 40, y: 40)
    @State private var lastMoveAt = Date()
    @State private var accLP = CGVector(dx: 0, dy: 0)

    // Wander
    @State private var wander = CGVector(dx: 0, dy: 0)
    @State private var wanderTarget = CGVector(dx: 0, dy: 0)
    @State private var lastWanderUpdate = Date()

    // Edge dwell → escape / center cruise
    @State private var lastTickAt = Date()
    @State private var edgeDwell: Double = 0
    @State private var escapeUntil: Date? = nil
    @State private var centerCruiseUntil: Date? = nil
    @State private var lastCenterCruise = Date(timeIntervalSince1970: 0)

    private let motion = CMMotionManager()
    // keep your current tick
    @State private var ticker = Timer.publish(every: 1/140, on: .main, in: .common).autoconnect()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.88))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))

                Group {
                    if let ch = letterChar {
                        Text(String(ch))
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(PremiumPalette.accent.opacity(0.25)))
                    } else {
                        Circle().fill(.white.opacity(0.25)).frame(width: 20, height: 20)
                    }
                }
                .scaleEffect(letterScale)
                .opacity(letterOpacity)
                .position(target)

                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(radius: 2, y: 1)
                    .scaleEffect(ballScale)
                    .position(ball)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                guard !solved else { return }
                                ball = clamp(point: g.location, in: geo.size)
                                lastMoveAt = Date()
                                lastBallPos = ball
                            }
                            .onEnded { _ in checkCatch(in: geo.size) }
                    )

                RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1), lineWidth: 8)

                TimelineView(.animation) { tl in
                    if let start = captureAt {
                        let dt = tl.date.timeIntervalSince(start)
                        Canvas { ctx, _ in
                            let c = target
                            for i in 0..<3 {
                                let t = dt - Double(i) * 0.06
                                guard t >= 0 else { continue }
                                let dur: Double = reduceMotion ? 0.25 : 0.6
                                guard t <= dur else { continue }
                                let p = t / dur
                                let r = CGFloat(10 + p * 120)
                                let a = 1.0 - p
                                let rect = CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2)
                                ctx.stroke(Circle().path(in: rect),
                                           with: .color(.white.opacity(0.35 * a)),
                                           lineWidth: 2)
                            }
                        }
                    }
                }
            }
            .onReceive(ticker) { _ in
                guard !solved else { return }

                // --- timing / dt ---
                let now = Date()
                let dt = max(0.0, now.timeIntervalSince(lastTickAt))
                lastTickAt = now

                // --- idle detection ---
                let moveDist = hypot(ball.x - lastBallPos.x, ball.y - lastBallPos.y)
                if moveDist > 0.4 { lastMoveAt = now }
                lastBallPos = ball
                let isIdle = now.timeIntervalSince(lastMoveAt) > 0.45

                // --- wander update (idle = slower, smaller) ---
                let wanderPeriod = isIdle ? 1.2 : 0.7
                if now.timeIntervalSince(lastWanderUpdate) > wanderPeriod {
                    let a = Double.random(in: 0..<(2 * .pi))
                    let m = Double.random(in: (isIdle ? 0.05...0.22 : 0.20...0.55))
                    wanderTarget = CGVector(dx: CGFloat(cos(a) * m), dy: CGFloat(sin(a) * m))
                    lastWanderUpdate = now
                }
                // ease toward wander target
                let wanderEase: CGFloat = isIdle ? 0.03 : 0.05
                wander.dx += (wanderTarget.dx - wander.dx) * wanderEase
                wander.dy += (wanderTarget.dy - wander.dy) * wanderEase

                // --- geometry ---
                var p = target
                var acc = CGVector(dx: 0, dy: 0)

                let inset: CGFloat = 36
                let minX = inset, maxX = geo.size.width - inset
                let minY = inset, maxY = geo.size.height - inset
                let center = CGPoint(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5)

                let toBall = CGVector(dx: ball.x - p.x, dy: ball.y - p.y)
                let dist = max(0.001, hypot(toBall.dx, toBall.dy))
                let dirToBall = CGVector(dx: toBall.dx / dist, dy: toBall.dy / dist)
                let toCenter = CGVector(dx: center.x - p.x, dy: center.y - p.y)
                let lenC = max(0.001, hypot(toCenter.dx, toCenter.dy))
                let dirToCenter = CGVector(dx: toCenter.dx/lenC, dy: toCenter.dy/lenC)
                let perpToBall = CGVector(dx: -dirToBall.dy, dy: dirToBall.dx)
                let tangentSign: CGFloat = (perpToBall.dx * dirToCenter.dx + perpToBall.dy * dirToCenter.dy) >= 0 ? 1 : -1

                // --- wall distances / dwell ---
                let wallRange: CGFloat = 70
                let dxL = p.x - minX, dxR = maxX - p.x
                let dyT = p.y - minY, dyB = maxY - p.y
                let nearEdgeDist = min(min(dxL, dxR), min(dyT, dyB))
                let nearEdge = nearEdgeDist < 34

                // Accumulate edge dwell time and trigger escape
                if nearEdge { edgeDwell += dt } else { edgeDwell = max(0, edgeDwell - dt * 1.5) }
                if edgeDwell > 0.85, escapeUntil == nil {
                    escapeUntil = now.addingTimeInterval(0.7)
                    edgeDwell = 0.25
                }

                // Periodic short center cruises if hanging around borders a lot
                let needCruise = (nearEdge && now.timeIntervalSince(lastCenterCruise) > 2.6)
                if needCruise {
                    centerCruiseUntil = now.addingTimeInterval(0.5)
                    lastCenterCruise = now
                }

                let inEscape = (escapeUntil.map { now < $0 } ?? false)
                let inCruise  = (centerCruiseUntil.map { now < $0 } ?? false)

                // 1) Flee player (so it doesn’t run *toward* you)
                let safeRadius: CGFloat  = 180
                let panicRadius: CGFloat = 80
                let tClose = max(0, min(1, (safeRadius - dist) / (safeRadius - panicRadius)))
                let fleeBase: CGFloat  = isIdle ? 0.15 : 0.50
                let fleeScale: CGFloat = isIdle ? 1.20 : 2.00
                let fleeMag = (inEscape || inCruise) ? (fleeBase * 0.65) : (fleeBase + fleeScale * tClose)
                acc.dx += -dirToBall.dx * fleeMag
                acc.dy += -dirToBall.dy * fleeMag

                // 2) Side-step around player (reduced when idle; curved when cruising)
                let slipMag = (isIdle ? 0.10 : 0.25) + (isIdle ? 0.30 : 0.80) * tClose
                let curveBoost: CGFloat = inCruise ? 0.35 : 0
                acc.dx += perpToBall.dx * (tangentSign * (slipMag + curveBoost))
                acc.dy += perpToBall.dy * (tangentSign * (slipMag + curveBoost))

                // 3) Wall & corner repulsion (softer when idle/escaping)
                func push(_ d: CGFloat, scale: CGFloat) -> CGFloat {
                    guard d < wallRange else { return 0 }
                    let x = max(0, (wallRange - d) / wallRange) // 0..1
                    return scale * x * x
                }
                let wallScale: CGFloat = (isIdle || inEscape || inCruise) ? 1.0 : 2.1
                acc.dx += push(dxL, scale: wallScale) - push(dxR, scale: wallScale)
                acc.dy += push(dyT, scale: wallScale) - push(dyB, scale: wallScale)

                // Corner escape (extra nudge when stuck in the L of a corner)
                let cornerRange: CGFloat = 44
                if min(dxL, dxR) < cornerRange && min(dyT, dyB) < cornerRange {
                    let nx: CGFloat = (dxL < dxR) ? 1 : -1
                    let ny: CGFloat = (dyT < dyB) ? 1 : -1
                    let norm = 1 / max(0.001, hypot(nx, ny))
                    let boost: CGFloat = (isIdle || inEscape || inCruise) ? 1.4 : 2.2
                    acc.dx += nx * norm * boost
                    acc.dy += ny * norm * boost
                }

                // 4) Escape/Cruise: strong gentle pull to center + orbit, to break wall-hugging
                if inEscape || inCruise {
                    acc.dx += dirToCenter.dx * (inEscape ? 0.70 : 0.55)
                    acc.dy += dirToCenter.dy * (inEscape ? 0.70 : 0.55)
                    // small center orbit for natural curve inward
                    let perpC = CGVector(dx: -dirToCenter.dy, dy: dirToCenter.dx)
                    acc.dx += perpC.dx * 0.25 * (tangentSign)
                    acc.dy += perpC.dy * 0.25 * (tangentSign)
                } else if isIdle {
                    // idle: faint center pull to avoid camping near borders
                    acc.dx += dirToCenter.dx * 0.25
                    acc.dy += dirToCenter.dy * 0.25
                } else {
                    // active & free: tiny orbit around center for nicer trajectories
                    let perpC = CGVector(dx: -dirToCenter.dy, dy: dirToCenter.dx)
                    acc.dx += perpC.dx * 0.10 * tangentSign
                    acc.dy += perpC.dy * 0.10 * tangentSign
                }

                // 5) Add low-frequency wander
                acc.dx += wander.dx
                acc.dy += wander.dy

                // ---- Low-pass smoothing of steering ----
                accLP.dx = accLP.dx * 0.90 + acc.dx * 0.10
                accLP.dy = accLP.dy * 0.90 + acc.dy * 0.10

                let desiredDX = velTarget.dx + accLP.dx
                let desiredDY = velTarget.dy + accLP.dy

                velTarget.dx += (desiredDX - velTarget.dx) * 0.12
                velTarget.dy += (desiredDY - velTarget.dy) * 0.12

                // Never steer toward the ball (project out "toward" component)
                let towardDot = velTarget.dx * dirToBall.dx + velTarget.dy * dirToBall.dy
                if towardDot > 0 {
                    velTarget.dx -= dirToBall.dx * towardDot * 1.05
                    velTarget.dy -= dirToBall.dy * towardDot * 1.05
                }

                // Idle damping & dead-zone to kill micro-jitter
                if isIdle {
                    velTarget.dx *= 0.97
                    velTarget.dy *= 0.97
                    let dz: CGFloat = 0.08
                    if abs(velTarget.dx) < dz { velTarget.dx = 0 }
                    if abs(velTarget.dy) < dz { velTarget.dy = 0 }
                }

                // Keep your per-axis clamp
                velTarget.dx = clampMag(velTarget.dx, maxValue: 2.6)
                velTarget.dy = clampMag(velTarget.dy, maxValue: 2.6)

                // Integrate + soft bounce
                p.x += velTarget.dx
                p.y += velTarget.dy

                let hitLeft  = p.x < minX
                let hitRight = p.x > maxX
                let hitTop   = p.y < minY
                let hitBot   = p.y > maxY

                if hitLeft  { p.x = minX; velTarget.dx *= -0.95 }
                if hitRight { p.x = maxX; velTarget.dx *= -0.95 }
                if hitTop   { p.y = minY; velTarget.dy *= -0.95 }
                if hitBot   { p.y = maxY; velTarget.dy *= -0.95 }

                // Flush from exact wall so it doesn’t skate along the border pixels
                if hitLeft  { p.x += 0.8 }
                if hitRight { p.x -= 0.8 }
                if hitTop   { p.y += 0.8 }
                if hitBot   { p.y -= 0.8 }

                target = p
                checkCatch(in: geo.size)
            }
            .onAppear {
                // Freeze letter once
                letterChar = hasLetter ? (seed ?? PremiumHubModel.randomLetter()) : nil

                // Safe spawn
                let inset: CGFloat = 36
                ball = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                               y: .random(in: inset...(geo.size.height - inset)))
                target = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                 y: .random(in: inset...(geo.size.height - inset)))
                lastBallPos = ball
                lastMoveAt = Date()
                lastTickAt = Date()

                // Motion for the ball
                if motion.isDeviceMotionAvailable {
                    motion.deviceMotionUpdateInterval = 1/60
                    motion.startDeviceMotionUpdates(to: .main) { data, _ in
                        guard !solved, let g = data?.gravity else { return }
                        velBall.dx += CGFloat(g.x) * 1.6
                        velBall.dy -= CGFloat(g.y) * 1.6
                        velBall.dx *= 0.98; velBall.dy *= 0.98
                        var next = CGPoint(x: ball.x + velBall.dx, y: ball.y + velBall.dy)
                        next = clamp(point: next, in: geo.size)
                        if hypot(next.x - ball.x, next.y - ball.y) > 0.2 { lastMoveAt = Date() }
                        ball = next
                        checkCatch(in: geo.size)
                    }
                }
            }
            .onDisappear { motion.stopDeviceMotionUpdates() }
        }
        .frame(height: 280)
    }

    // MARK: - Helpers

    private func clamp(point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: max(20, min(size.width - 20, point.x)),
                y: max(20, min(size.height - 20, point.y)))
    }

    private func clampMag(_ v: CGFloat, maxValue: CGFloat) -> CGFloat {
        min(maxValue, max(-maxValue, v))
    }

    private func checkCatch(in size: CGSize, threshold: CGFloat = 18) {
        guard !solved else { return }
        if hypot(ball.x - target.x, ball.y - target.y) <= threshold {
            solved = true
            captureAt = Date()

            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            motion.stopDeviceMotionUpdates()

            let snapDur = reduceMotion ? 0.15 : 0.28
            let popDur  = reduceMotion ? 0.15 : 0.28

            withAnimation(.spring(response: snapDur, dampingFraction: 0.75)) {
                ball = target
                ballScale = 1.15
            }
            withAnimation(.spring(response: popDur, dampingFraction: 0.7)) {
                letterScale = 1.18
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.10 : 0.18)) {
                withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) {
                    letterScale = 0.82
                    letterOpacity = 0.0
                    ballScale = 1.0
                }
            }

            let resolveDelay = reduceMotion ? 0.35 : 0.65
            DispatchQueue.main.asyncAfter(deadline: .now() + resolveDelay) {
                if let ch = letterChar { onDone(.found(ch)) } else { onDone(.nothing) }
            }
        }
    }
}

// MARK: - NEW: AI Merchant (now uses hub to offer undiscovered letters and window preference)

private struct AIMerchantMini: View {
    let deadline: Date
    let ai: AIDifficulty?
    let hub: PremiumHubModel
    var onDone: (MiniResult) -> Void
    
    @State private var offered: [Character] = []
    @State private var picked: Set<Character> = []
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let ai {
                    Image(ai.rawValue.image)
                        .resizable().scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ai.rawValue.name).font(.subheadline.weight(.semibold))
                        Text("take this".localized).font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                } else { Text("Unavailable".localized).font(.subheadline) }
                Spacer()
                CountdownPill(deadline: deadline)
            }
            .padding(.bottom, 6)
            
            // Spaced AI tokens (adaptive grid)
            WrapLetters(letters: offered, picked: picked, spacing: 6, runSpacing: 8) { ch in
                guard !picked.contains(ch) else { return }
                picked.insert(ch)
                onDone(.found(ch))
                if picked.count == offered.count { onDone(.close) }
            }
        }
        .onAppear {
            let count = ai?.premiumLetterCount ?? 0
            offered = hub.pickLettersForOffer(count: count).shuffled()
        }
    }
}

private struct CountdownPill: View {
    let deadline: Date
    @State private var now = Date()
    var body: some View {
        let s = max(0, Int(deadline.timeIntervalSince(now).rounded()))
        Text("\(s)s")
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.12)))
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { d in now = d }
    }
}

// MARK: - FlowLayout (kept for other views if needed)
fileprivate struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var runSpacing: CGFloat = 8
    
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0
        
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxWidth {
                maxLineWidth = max(maxLineWidth, x - spacing)
                x = 0
                y += lineHeight + runSpacing
                lineHeight = 0
            }
            x += (x > 0 ? spacing : 0) + sz.width
            lineHeight = max(lineHeight, sz.height)
        }
        maxLineWidth = max(maxLineWidth, x)
        return CGSize(width: maxLineWidth, height: y + lineHeight)
    }
    
    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxWidth {
                x = 0
                y += lineHeight + runSpacing
                lineHeight = 0
            }
            s.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(width: sz.width, height: sz.height)
            )
            x += (x > 0 ? spacing : 0) + sz.width
            lineHeight = max(lineHeight, sz.height)
        }
    }
}

private struct ThickGlassCell: View {
    let character: Character
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
            Text(String(character))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .scaleEffect(1.06)
                .opacity(0.85)
                .blur(radius: 1.2)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thickMaterial)
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.10), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .blendMode(.screen)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
                .overlay(GlassSpeckle().opacity(0.05)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                .shadow(color: .black.opacity(0.30), radius: 7, y: 3)
                .allowsHitTesting(false)
        }
        .frame(height: 56)
    }
}

fileprivate struct GlassSpeckle: View {
    var body: some View {
        Canvas { ctx, size in
            for _ in 0..<36 {
                let r = CGFloat.random(in: 0.6...1.6)
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                ctx.fill(
                    Ellipse().path(in: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(.white.opacity(0.8))
                )
            }
        }
        .blur(radius: 0.8)
    }
}

fileprivate struct WrapLetters: View {
    let letters: [Character]
    let picked: Set<Character>
    var spacing: CGFloat = 14
    var runSpacing: CGFloat = 12
    let tap: (Character) -> Void
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: spacing)],
                  spacing: runSpacing) {
            ForEach(letters, id: \.self) { ch in
                Button { tap(ch) } label: {
                    Text(String(ch))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(PremiumPalette.accent))
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                        .opacity(picked.contains(ch) ? 0.25 : 1)
                        .scaleEffect(picked.contains(ch) ? 0.82 : 1)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8),
                                   value: picked.contains(ch))
                }
                .disabled(picked.contains(ch))
            }
        }
                  .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - NEW: Symbol Pick (blurred grid) – uses hub for letter supply

private struct SymbolPickMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    var onDone: (MiniResult) -> Void
    
    @State private var grid: [(Character, Bool)] = []   // (char, isLetter)
    @State private var attemptsLeft: Int = 3
    @State private var tried: Set<Int> = []             // wrong picks
    @State private var fired: Set<Int> = []             // pressed this finger already
    @State private var revealed: Set<Int> = []          // for pop/reveal
    @State private var successIndex: Int? = nil
    
    private let animDuration: Double = 0.30
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Tap a letter".localized).font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 8) {
                    // ••• + x/3
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(i < attemptsLeft ? .white.opacity(0.9) : .white.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text("\(attemptsLeft)/3")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.vertical, 3).padding(.horizontal, 6)
                        .background(Capsule().fill(.white.opacity(0.12)))
                    CountdownPill(deadline: deadline)
                }
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(0..<grid.count, id: \.self) { i in
                    let (ch, isL) = grid[i]
                    let isWrong = tried.contains(i)
                    let isRevealed = revealed.contains(i)
                    let isWin = (successIndex == i)
                    
                    ZStack {
                        // base glass tile
                        ThickGlassCell(character: ch)
                            .opacity(isWrong ? 0.95 : 1.0)
                        
                        // REVEAL glyph ABOVE the glass when revealed (and not wrong)
                        if isRevealed && !isWrong {
                            Text(String(ch))
                                .font(.system(.title, design: .rounded).weight(.heavy))
                                .foregroundStyle(.white)
                                .shadow(radius: 3, y: 1)
                                .transition(.scale.combined(with: .opacity))
                                .scaleEffect(isWin ? 1.08 : 1.02)
                                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRevealed)
                        }
                        
                        // wrong mark
                        if isWrong {
                            Image(systemName: "slash.circle")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .transition(.opacity)
                        }
                        
                        if isWin {
                            RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 3)
                                .shadow(radius: 6)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .scaleEffect(isRevealed ? 1.05 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRevealed)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // commit on touch-down; can’t cancel by dragging out
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !fired.contains(i),
                                      successIndex == nil,
                                      !isWrong,
                                      attemptsLeft > 0 else { return }
                                fired.insert(i)
                                select(i: i, isLetter: isL, ch: ch)
                            }
                    )
                    .allowsHitTesting(!isWrong && successIndex == nil && attemptsLeft > 0)
                }
            }
        }
        .onAppear {
            fired.removeAll()
            var items: [(Character, Bool)] = (0..<16).map { _ in
                Bool.random()
                ? (hub.pickLetterForOffer(), true)
                : (PremiumHubModel.randomNonLetter(), false)
            }
            if !items.contains(where: { $0.1 }) {
                items[Int.random(in: 0..<items.count)] = (hub.pickLetterForOffer(), true)
            }
            grid = items.shuffled()
        }
    }
    
    @MainActor
    private func select(i: Int, isLetter: Bool, ch: Character) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            _ = revealed.insert(i)
        }
        attemptsLeft -= 1
        
        if isLetter {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                successIndex = i
            }
            // close AFTER the reveal plays
            Task {
                try? await Task.sleep(nanoseconds: UInt64(animDuration * 2_000_000_000))
                onDone(.found(ch))
            }
        } else {
            tried.insert(i)
            if attemptsLeft == 0 {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(animDuration * 1_000_000_000))
                    onDone(.nothing)
                }
            }
        }
    }
}



// MARK: - NEW: Symbol Puzzle (rotate & decide) – uses hub for letter

private struct SymbolPuzzleMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    var onDone: (MiniResult) -> Void
    
    @State private var symbol: Character = "?"
    @State private var isLetter = false
    @State private var angle: Double = [0, 90, 180, 270].randomElement()!
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Is this a letter?".localized).font(.subheadline.weight(.semibold))
                Spacer()
                CountdownPill(deadline: deadline)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                Text(String(symbol))
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(angle))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: angle)
                    .padding(10)
            }
            .frame(height: 200)
            HStack(spacing: 12) {
                Button { angle -= 90 } label: {
                    Label("Rotate", systemImage: "rotate.left")
                }
                .buttonStyle(.borderedProminent)
                
                Button { angle += 90 } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    let upright = Int(((angle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360))
                    if isLetter && upright % 360 == 0 {
                        onDone(.found(symbol))
                    } else {
                        onDone(.nothing)
                    }
                } label: { Text("Yes".localized).bold() }
                    .buttonStyle(.borderedProminent)
                
                Button { onDone(.nothing) } label: { Text("No".localized) }
                    .buttonStyle(.bordered)
            }
        }
        .onAppear {
            if Bool.random() {
                symbol = hub.pickLetterForOffer()
                isLetter = true
            } else {
                symbol = PremiumHubModel.randomNonLetter()
                isLetter = false
            }
        }
    }
}

// MARK: - NEW: Lucky Wait – uses hub for letter

private struct LuckyWaitMini: View {
    let deadline: Date
    let hub: PremiumHubModel
    var onDone: (MiniResult) -> Void
    
    @State private var started = Date()
    @State private var resolved = false
    @State private var showLetter: Character? = nil
    @State private var showNo = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Wait 5 seconds…".localized).font(.subheadline.weight(.semibold))
                Spacer()
                CountdownPill(deadline: deadline)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1)))
                    .frame(height: 140)
                if let ch = showLetter {
                    Text(String(ch))
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else if showNo {
                    Text("No letter".localized)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .transition(.opacity)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
        }
        .onAppear { started = Date() }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { now in
            guard !resolved else { return }
            if now.timeIntervalSince(started) >= 5 {
                resolved = true
                if Bool.random() {
                    let ch = hub.pickLetterForOffer()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showLetter = ch
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        onDone(.found(ch))
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.35)) { showNo = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        onDone(.nothing)
                    }
                }
            }
        }
    }
}

// MARK: - Haptics

private func lightTap(_ engine: CHHapticEngine?) {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
    let evt = CHHapticEvent(eventType: .hapticTransient, parameters: [
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5)
    ], relativeTime: 0)
    try? engine?.start()
    try? engine?.makePlayer(with: CHHapticPattern(events: [evt], parameters: [])).start(atTime: 0)
}

private func success(_ engine: CHHapticEngine?) {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
    let evts = [
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: 0.7),
            .init(parameterID: .hapticSharpness, value: 0.6)
        ], relativeTime: 0),
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: 1.0),
            .init(parameterID: .hapticSharpness, value: 0.9)
        ], relativeTime: 0.12)
    ]
    try? engine?.start()
    try? engine?.makePlayer(with: CHHapticPattern(events: evts, parameters: [])).start(atTime: 0)
}

private func warn(_ engine: CHHapticEngine?) {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
    let evts = [
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: 0.5),
            .init(parameterID: .hapticSharpness, value: 0.2)
        ], relativeTime: 0)
    ]
    try? engine?.start()
    try? engine?.makePlayer(with: CHHapticPattern(events: [evts[0]], parameters: [])).start(atTime: 0)
}

// MARK: - Utils

private extension Binding where Value == String {
    func limit(toAllowed allowed: Set<Character>) -> Binding<String> {
        Binding<String>(
            get: { wrappedValue },
            set: { newValue in
                let up = newValue.uppercased()
                let filtered = up.filter { $0.isLetter && allowed.contains($0) }
                self.wrappedValue = String(filtered.prefix(10))
            }
        )
    }
}

extension String {
    /// True if every *letter* in the string appears in `allowed`, ignoring case.
    func lettersAreSubset(of allowed: Set<Character>, locale: Locale = .current) -> Bool {
        let allowedLower: Set<Character> = Set(
            allowed.compactMap { ch in
                let s = String(ch).lowercased(with: locale)
                return s.count == 1 ? s.first : nil
            }
        )
        let allowedStrings = allowed.map(String.init)
        
        for ch in self {
            let isLetter = ch.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            guard isLetter else { continue }
            
            let s = String(ch).lowercased(with: locale)
            if s.count == 1, let c = s.first {
                if !allowedLower.contains(c) { return false }
            } else {
                if !allowedStrings.contains(where: {
                    $0.compare(String(ch), options: [.caseInsensitive], range: nil, locale: locale) == .orderedSame
                }) {
                    return false
                }
            }
        }
        return true
    }
}
