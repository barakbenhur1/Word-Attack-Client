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
    @Published var total: Int = 90
    func set(_ s: Int, total t: Int) { secondsLeft = s; total = t }
}

// MARK: - Entry

public struct PremiumHubView: View {
    @EnvironmentObject private var timerBridge: HubTimerBridge
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    
    private var language: String? { local.locale.identifier.components(separatedBy: "_").first }
    @StateObject private var hub: PremiumHubModel
    @State private var engine: CHHapticEngine? = try? CHHapticEngine()
    
    @State private var presentedSlot: MiniSlot?
    @State private var activeSlot: MiniSlot?
    @State private var didResolveSheet = false
    
    @AppStorage("wins_count") private var solvedWords: Int = 0
    
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
                    
                    Grid3x3(hub: hub, presentedSlot: $presentedSlot, engine: engine, reset: {})
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
                            Image(systemName: "arrow.right")
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
                    hub.stop()
                    router.navigateBack()
                }
                Spacer()
                SolvedCounterPill(count: solvedWords)
                MainRoundTimerView(secondsLeft: hub.mainSecondsLeft, total: hub.mainRoundLength)
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
                    success(engine)
                    if slot.kind != .aiMerchant { close() }
                case .foundMany(let chars):
                    for ch in chars { hub.discoveredLetters.insert(ch) }
                    success(engine); close()
                case .nothing:
                    warn(engine); close()
                case .close:
                    close()
                }
            }
            .presentationDetents([.medium, .large])
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
        //        .onDisappear { hub.stop() }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - Top bar

private struct BackPill: View {
    var action: () -> Void
    var body: some View { BackButton() }
}

// 🏆 Pill showing solved words count
private struct SolvedCounterPill: View {
    let count: Int
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
    }
}

// MARK: - Palette

private enum PremiumPalette {
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
        case .gyro: "Gyro Maze".localized
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
        case .gyro: "gyroscope"
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
    @Published private(set) var mainSecondsLeft: Int = 180
    let mainRoundLength = 180
    
    @Published var discoveredLetters: Set<Character> = []
    @Published var canInteract: Bool = true
    @Published var aiDifficulty: AIDifficulty? = nil
    
    let vm = PremiumHubViewModel()
    private var tick: AnyCancellable?
    private let email: String?
    
    init(email: String?) {
        self.email = email
        self.aiDifficulty = loadAIDifficulty()
    }
    
    /// Refresh AI difficulty and purge any existing AI-Merchant slots if AI is disabled.
    func refreshAIDifficulty() {
        self.aiDifficulty = loadAIDifficulty()
        if aiDifficulty == nil {
            // Replace any existing AI Merchant slots immediately so chance is truly 0%.
            slots = slots.map { $0.kind == .aiMerchant ? Self.makeSlot(hasAI: false) : $0 }
        }
    }
    
    func start() {
        if slots.isEmpty {
            slots = (0..<8).map { _ in Self.makeSlot(hasAI: aiDifficulty != nil) }
        } else if aiDifficulty == nil {
            // Safety: if AI was turned off while slots already existed.
            slots = slots.map { $0.kind == .aiMerchant ? Self.makeSlot(hasAI: false) : $0 }
        }
        
        if vm.word == .empty, let email {
            Task(priority: .userInitiated) { await self.vm.word(email: email) }
        }
        guard tick == nil else { return }
        tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.mainSecondsLeft -= 1
                if self.mainSecondsLeft <= 0 { resetTimer() }
                self.slots = self.slots.map { s in
                    s.expiresAt <= Date() ? Self.makeSlot(hasAI: self.aiDifficulty != nil) : s
                }
            }
    }
    
    private func resetTimer() {
        self.mainSecondsLeft = self.mainRoundLength
        self.discoveredLetters = []
        if let email {
            Task(priority: .userInitiated) { await self.vm.word(email: email) }
        }
    }
    
    func resetAll() {
        self.slots = (0..<8).map { _ in Self.makeSlot(hasAI: aiDifficulty != nil) }
        resetTimer()
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
        slots[i] = Self.makeSlot(hasAI: aiDifficulty != nil)
    }
    
    private static func selectKind(hasAI: Bool) -> MiniKind {
        // Requested appearance rates (must sum to 100 when AI is enabled)
        // sand 11, wax 11, fog 11, sonar 11, ripple 11,
        // magnet 10, frost 9, gyro 8, aiMerchant 3, symbolPick 5,
        // symbolPuzzle 5, luckyWait 5
        var weights: [(MiniKind, Double)] = [
            (.sand, 11), (.wax, 11), (.fog, 11), (.sonar, 11), (.ripple, 11),
            (.magnet, 10), (.frost, 9), (.gyro, 8),
            (.aiMerchant, 3),
            (.symbolPick, 5), (.symbolPuzzle, 5), (.luckyWait, 5)
        ]
        if !hasAI {
            // ABSOLUTE: 0% chance to show AI Merchant when AI is nil
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
    
    private static func makeSlot(hasAI: Bool) -> MiniSlot {
        let kind = selectKind(hasAI: hasAI)
        let contains: Bool
        let seed: Character?
        let ttl: Int
        
        switch kind {
        case .aiMerchant:
            contains = true; seed = nil; ttl = 20
        case .symbolPick:
            contains = true; seed = nil; ttl = 15
        case .symbolPuzzle:
            contains = true; seed = nil; ttl = 30
        case .luckyWait:
            contains = false; seed = nil; ttl = 12   // 12s slot TTL
        default:
            contains = Double.random(in: 0...1) < kind.baseLetterChance
            seed = contains ? randomLetter() : nil
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
    let reset: () -> Void
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
                                MainRoundCircle(hub: hub, reset: reset)
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

// MARK: - Main circle

private struct MainRoundCircle: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var vm: PremiumHubViewModel
    @ObservedObject var hub: PremiumHubModel
    let reset: () -> Void
    
    var body: some View {
        Button {
            router.navigateTo(.premiumGame(word: vm.word.value,
                                           allowedLetters: String(hub.discoveredLetters).lowercased()))
        } label: {
            ZStack {
                Circle()
                    .fill(PremiumPalette.card)
                    .overlay(Circle().stroke(PremiumPalette.stroke, lineWidth: 1))
                    .shadow(color: PremiumPalette.glow, radius: 10, y: 6)
                VStack(spacing: 8) {
                    AppTitle().shadow(radius: 4).scaleEffect(.init(width: 0.7, height: 0.7)).padding(.all, -8)
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { i in
                            let show = i < min(5, hub.discoveredLetters.count)
                            Circle()
                                .fill(show ? .white : .white.opacity(0.25))
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.5))
                        }
                    }.padding(.bottom, 4)
                }.padding(10)
            }
        }
        .tint(.black)
        .onAppear { router.onForceEndPremium = reset }
        .onDisappear { router.onForceEndPremium = {} }
    }
}

// MARK: - Tile

private struct MiniGameSlotView: View {
    let slot: MiniSlot
    var ai: AIDifficulty?
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Show the fancy AI ring only when AI is enabled
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
                case .sand:   SandDigMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .wax:    WaxPressMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .fog:    FogWipeMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .sonar:  SonarMini(letter: slot.seededLetter ?? PremiumHubModel.randomLetter(), onDone: onDone)
                case .ripple: RippleMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .magnet: MagnetMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .frost:  FrostMini(hasLetter: slot.containsLetter, letter: slot.seededLetter, onDone: onDone)
                case .gyro:   GyroMazeMini(letter: slot.seededLetter ?? PremiumHubModel.randomLetter(), onDone: onDone)
                case .aiMerchant: AIMerchantMini(deadline: slot.expiresAt, ai: hub.aiDifficulty, onDone: onDone)
                case .symbolPick: SymbolPickMini(deadline: slot.expiresAt, onDone: onDone)
                case .symbolPuzzle: SymbolPuzzleMini(deadline: slot.expiresAt, onDone: onDone)
                case .luckyWait: LuckyWaitMini(deadline: slot.expiresAt, onDone: onDone)
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
    private var progress: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(secondsLeft) / Double(total)))
    }
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * progress
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(LinearGradient(colors: [PremiumPalette.accent, PremiumPalette.accent2],
                                              startPoint: .leading, endPoint: .trailing))
                .frame(width: w)
            }
        }
        .overlay(
            HStack(spacing: 6) {
                Text("\(secondsLeft)s").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.9))
                Text("round".localized).font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
                .padding(.horizontal, 6),
            alignment: .trailing
        )
        .clipShape(Capsule())
        .frame(height: 18)
    }
}

// MARK: - Legacy Minis (unchanged behavior)

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
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(PremiumPalette.wax)
                    .overlay(
                        LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .opacity(0.7 - 0.6 * clarity)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.9))
                        .position(letterPos)
                        .mask(Group {
                            if let p = pressPoint {
                                Circle()
                                    .size(CGSize(width: 40 + 140 * clarity, height: 40 + 140 * clarity))
                                    .offset(x: p.x - (20 + 70 * clarity), y: p.y - (20 + 70 * clarity))
                            }
                        })
                        .animation(.easeInOut(duration: 0.15), value: clarity)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in pressPoint = g.location; clarity = min(1, clarity + 0.02) }
                .onEnded { _ in
                    let success = hasLetter && overlap(pressPoint ?? .zero, letterPos, clarity: clarity)
                    onDone(success ? .found(seeded) : .nothing)
                    pressPoint = nil; clarity = 0
                })
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                letterPos = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                    y: .random(in: inset...(geo.size.height - inset)))
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
    let letter: Character
    let onDone: (MiniResult) -> Void
    @State private var target: CGPoint = .zero
    @State private var pings: [Ping] = []
    @State private var solved = false
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
                if solved {
                    Text(String(letter))
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onDone(.found(letter)) }
                }
            })
            .onAppear {
                let inset: CGFloat = 70
                target = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                 y: .random(in: inset...(geo.size.height - inset)))
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
    var body: some View {
        GeometryReader { geo in
            let bounds = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                Canvas { ctx, _ in
                    var path = Path()
                    for _ in 0..<7 {
                        let w = Double.random(in: 60...90)
                        let h = Double.random(in: 10...16)
                        let x = Double.random(in: 20...(bounds.width-80))
                        let y = Double.random(in: 20...(bounds.height-20))
                        path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: 7, height: 7))
                    }
                    ctx.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 5)
                }
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(bounds.width, bounds.height) * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.04))
                        .position(letterPos)
                }
                Canvas { ctx, _ in
                    for f in filings {
                        let rect = CGRect(x: f.p.x - 2, y: f.p.y - 2, width: 4, height: 4)
                        ctx.fill(Ellipse().path(in: rect), with: .color(.white.opacity(0.8)))
                    }
                }
                Image(systemName: "paperclip.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(PremiumPalette.accent)
                    .position(magnetPos)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in magnetPos = g.location }
                        .onEnded { _ in
                            let d = hypot(magnetPos.x - letterPos.x, magnetPos.y - letterPos.y)
                            onDone((hasLetter && d < 46) ? .found(seeded) : .nothing)
                        })
            }
            .onReceive(physicsTimer) { _ in
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
                if hasLetter {
                    let d = hypot(magnetPos.x - letterPos.x, magnetPos.y - letterPos.y)
                    closeTicks = d < 48 ? (closeTicks + 1) : 0
                    if closeTicks > 15 { onDone(.found(seeded)) }
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
}

private struct FrostMini: View {
    let hasLetter: Bool
    let letter: Character?
    let onDone: (MiniResult) -> Void
    @State private var heatPoints: [CGPoint] = []
    @State private var letterPos: CGPoint = .zero
    @State private var seeded: Character = "A"
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.88))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                if hasLetter {
                    Text(String(seeded))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .position(letterPos)
                        .mask(HeatMask(points: heatPoints))
                }
                FrostOverlay().clipShape(RoundedRectangle(cornerRadius: 18)).opacity(0.9)
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in heatPoints.append(g.location) }
                .onEnded { _ in
                    let success = hasLetter && heatPoints.contains { hypot($0.x - letterPos.x, $0.y - letterPos.y) < 42 }
                    onDone(success ? .found(seeded) : .nothing)
                })
            .onAppear {
                seeded = letter ?? PremiumHubModel.randomLetter()
                let inset: CGFloat = 70
                letterPos = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                    y: .random(in: inset...(geo.size.height - inset)))
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
    let letter: Character
    let onDone: (MiniResult) -> Void
    @State private var ball = CGPoint(x: 40, y: 40)
    @State private var target = CGPoint(x: 260, y: 220)
    @State private var vel = CGVector(dx: 0, dy: 0)
    private let motion = CMMotionManager()
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.88))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(PremiumPalette.stroke, lineWidth: 1))
                Text(String(letter))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(PremiumPalette.accent.opacity(0.25)))
                    .position(target)
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(radius: 2, y: 1)
                    .position(ball)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in ball = g.location }
                        .onEnded { _ in checkSuccess() })
                RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1), lineWidth: 8)
            }
            .onAppear {
                let inset: CGFloat = 36
                ball = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                               y: .random(in: inset...(geo.size.height - inset)))
                target = CGPoint(x: .random(in: inset...(geo.size.width - inset)),
                                 y: .random(in: inset...(geo.size.height - inset)))
                if motion.isDeviceMotionAvailable {
                    motion.deviceMotionUpdateInterval = 1/60
                    motion.startDeviceMotionUpdates(to: .main) { data, _ in
                        guard let a = data?.gravity else { return }
                        vel.dx += CGFloat(a.x) * 1.6
                        vel.dy -= CGFloat(a.y) * 1.6
                        vel.dx *= 0.98; vel.dy *= 0.98
                        ball.x = max(20, min(geo.size.width-20, ball.x + vel.dx))
                        ball.y = max(20, min(geo.size.height-20, ball.y + vel.dy))
                        checkSuccess()
                    }
                }
            }
            .onDisappear { motion.stopDeviceMotionUpdates() }
        }
        .frame(height: 280)
    }
    private func checkSuccess() {
        if hypot(ball.x - target.x, ball.y - target.y) < 28 { onDone(.found(letter)) }
    }
}

// MARK: - NEW: AI Merchant

private struct AIMerchantMini: View {
    let deadline: Date
    let ai: AIDifficulty?
    var onDone: (MiniResult) -> Void
    
    @State private var offered: [Character] = []
    @State private var picked: Set<Character> = []
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let ai {
                    Image(ai.rawValue.image) // assets: easyAI / mediumAI / hardAI / bossAI
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
            var set: Set<Character> = []
            while set.count < count { set.insert(PremiumHubModel.randomLetter()) }
            offered = Array(set).shuffled()
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
            // faint base so background shines through
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
            
            // content behind the glass
            Text(String(character))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .scaleEffect(1.06)
                .opacity(0.85)
                .blur(radius: 1.2)
            
            // the glass itself – translucent
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
                        .stroke(.white.opacity(0.16), lineWidth: 1)  // crisp rim
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
        // Adaptive grid guarantees spacing & line breaks
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

// MARK: - NEW: Symbol Pick (blurred grid)

private struct SymbolPickMini: View {
    let deadline: Date
    var onDone: (MiniResult) -> Void
    
    @State private var grid: [(Character, Bool)] = [] // (char, isLetter)
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tap a letter".localized).font(.subheadline.weight(.semibold))
                Spacer()
                CountdownPill(deadline: deadline)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(0..<grid.count, id: \.self) { i in
                    let (ch, isL) = grid[i]
                    Button {
                        onDone(isL ? .found(ch) : .nothing)
                    } label: {
                        ThickGlassCell(character: ch)
                    }
                }
            }
        }
        .onAppear {
            var items: [(Character, Bool)] = []
            var letters: [Character] = []
            for _ in 0..<16 {
                if Bool.random() {
                    let l = PremiumHubModel.randomLetter()
                    items.append((l, true)); letters.append(l)
                } else {
                    items.append((PremiumHubModel.randomNonLetter(), false))
                }
            }
            if letters.isEmpty {
                let l = PremiumHubModel.randomLetter()
                items[Int.random(in: 0..<items.count)] = (l, true)
            }
            grid = items.shuffled()
        }
    }
}

// MARK: - NEW: Symbol Puzzle (rotate & decide)

private struct SymbolPuzzleMini: View {
    let deadline: Date
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
                symbol = PremiumHubModel.randomLetter()
                isLetter = true
            } else {
                symbol = PremiumHubModel.randomNonLetter()
                isLetter = false
            }
        }
    }
}

// MARK: - NEW: Lucky Wait
private struct LuckyWaitMini: View {
    let deadline: Date
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
                    let ch = PremiumHubModel.randomLetter()
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
