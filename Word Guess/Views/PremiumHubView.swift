//
//  PremiumHubView.swift
//  Uses MiniGameCatalog for kind selection + UI factory
//

import SwiftUI
import Combine
import CoreHaptics
import CoreMotion
import Foundation

enum HubGamePalette {
    static let card   = Color.dynamicBlack.opacity(0.06)
    static let stroke = Color.dynamicBlack.opacity(0.09)
    static let glow   = Color.dynamicBlack.opacity(0.22)
    static let accent = Color.cyan
    static let accent2 = Color.mint
}

// MARK: - AI Difficulty Loader (unchanged)
private func loadAIDifficulty() -> AIDifficulty? {
    guard let s = UserDefaults.standard.string(forKey: "aiDifficulty") else { return nil }
    switch s {
    case AIDifficulty.easy.name:   return .easy
    case AIDifficulty.medium.name: return .medium
    case AIDifficulty.hard.name:   return .hard
    case AIDifficulty.boss.name:   return .boss
    default: return nil
    }
}

// MARK: - Timer Bridge

final class HubTimerBridge: ObservableObject {
    @Published var secondsLeft: Int = 0
    @Published var total: Int = 0
    @Published var identity = 0
    
    func set(_ s: Int, total t: Int, bumpID: Bool = false) {
        secondsLeft = s
        total = t
        if bumpID { identity += 1 }
    }
}

// MARK: - Entry

public struct PremiumHubView: View {
    @Environment(\.colorScheme) private var scheme
    
    @EnvironmentObject private var timerBridge: HubTimerBridge
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    private var language: String? { local.locale.identifier.components(separatedBy: "_").first }
    private var uniqe: String? { loginHandeler.model?.uniqe }
    
    @StateObject private var hub: PremiumHubModel
    @State private var engine: CHHapticEngine?
    
    @State private var isOpen: Bool
    @State private var text: String
    @State private var duration: Double
    
    @State private var presentedSlot: MiniSlot?
    @State private var activeSlot: MiniSlot?
    @State private var didResolveSheet: Bool
    
    @State private var showError: Bool
    
    // Tutorial
    @State private var showTutorial: Bool
    
    private func handleError() {
        guard hub.vm.isError else { return }
        showError = true
    }
    
    private func closeView() {
        PremiumCoplitionHandler.shared.onForceEndPremium = { _, _ in }
        text = ""
        duration = 3
        withAnimation(.interpolatingSpring(duration: duration)) {
            isOpen = false
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_300_000_000)
            await MainActor.run {
                hub.stop()
                router.navigateBack()
            }
        }
    }
    
    public init(uniqe: String?) {
        isOpen = false
        text = "Premium Hub  💎"
        duration = 3
        didResolveSheet = false
        showError = false
        showTutorial = false
        engine = try? CHHapticEngine()
        _hub = StateObject(wrappedValue: PremiumHubModel(uniqe: uniqe))
    }
    
    public var body: some View {
        SlidingDoorOpen(isOpen: $isOpen, shimmer: true, text: text, duration: duration) {
            ZStack {
                PremiumBackground()
                VStack {
                    HStack(spacing: 12) {
                        BackPill { closeView() }
                            .padding(.trailing, 20)
                        SolvedCounterPill(
                            count: hub.solvedWords,
                            rank: hub.rank,
                            onTap: {
                                hub.pause()
                                router.navigateTo(.premiumScore)
                            }
                        )
                        timerView(secondsLeft: hub.mainSecondsLeft,
                                  timer: timerBridge,
                                  skipProgressAnimation: hub.isSkipProgressAnimation)
                        .padding(.trailing, 10)
                        .gesture(
                            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                                .onEnded { g in
                                    if abs(g.translation.width) > 60 {
                                        hub.resetAll()     // Timer animates its own reset; no layout changes
                                    }
                                }
                        )
                    }
                    .padding(.top, 4)
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Discover letters in tactile mini-games. Use them to solve the word.")
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(Color.dynamicBlack.opacity(0.7))
                                .padding(.top, 8)
                                .padding(.horizontal, 8)
                            
                            Grid3x3(hub: hub, presentedSlot: $presentedSlot, engine: engine)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Available letters")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.dynamicBlack.opacity(0.7))
                                DiscoveredBeltView(letters: Array(hub.discoveredLetters).sorted())
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            
                            if !UIDevice.isPad {
                                Button { lightTap(engine) } label: {
                                    HStack {
                                        Text("Find letters in mini-games")
                                        Spacer()
                                        Image(systemName: language == "he" ? "arrow.left" : "arrow.right")
                                    }
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.dynamicBlack)
                                    .padding(.horizontal, 16)
                                    .frame(height: 56)
                                    .background(LinearGradient(
                                        colors: scheme == .light
                                        ? [
                                            Color.white,
                                            Color(hue: 0.66, saturation: 0.06, brightness: 0.99)
                                        ]
                                        : [
                                            Color.black,
                                            Color(hue: 0.64, saturation: 0.25, brightness: 0.18)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing),
                                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    )
                                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.dynamicBlack.opacity(0.08)))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 28)
                    }
                    
                    if UIDevice.isPad {
                        Button { lightTap(engine) } label: {
                            HStack {
                                Text("Find letters in mini-games")
                                Spacer()
                                Image(systemName: language == "he" ? "arrow.left" : "arrow.right")
                            }
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.dynamicBlack)
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(LinearGradient(
                                colors: scheme == .light
                                ? [
                                    Color.white,
                                    Color(hue: 0.66, saturation: 0.06, brightness: 0.99)
                                ]
                                : [
                                    Color.black,
                                    Color(hue: 0.64, saturation: 0.25, brightness: 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.dynamicBlack.opacity(0.08)))
                        }
                        .padding(.bottom, 80)
                    }
                }
            }
            .environmentObject(hub.vm)
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
                        hub.recordFoundLetter(ch)
                        success(engine)
                        if slot.kind != .aiMerchant { close() }
                    case .foundMany(let chars):
                        for ch in chars {
                            hub.discoveredLetters.insert(ch)
                            hub.recordFoundLetter(ch)
                        }
                        success(engine); close()
                    case .nothing:
                        warn(engine); close()
                    case .close:
                        close()
                    }
                }
                // === SHEET BEHAVIOR FIX ===
                .presentationDetents([.medium])          // single detent → no resizing/peeking
                .presentationDragIndicator(.hidden)      // hide system grabber (we use our own)
                .interactiveDismissDisabled(true)        // stop pull-to-dismiss & finger-follow
                .ifAvailable_iOS17 {                     // iOS 17+: prevent background pans from jiggling the sheet
                    $0.presentationBackgroundInteraction(.disabled)
                }
            }
            .onChange(of: hub.vm.isError, handleError)
            .onChange(of: hub.mainSecondsLeft) { old, new in
                // Only bump identity on a RESET (seconds increasing). Prevents bump every second.
                let isReset = new > old
                timerBridge.set(new, total: hub.mainRoundLength, bumpID: isReset)
                if isReset { presentedSlot = nil }
            }
            .onAppear {
                hub.resume()
                hub.show()
                
                guard hub.vm.word == .empty else { return }
                
                text = "Premium Hub  💎"
                duration = 3
                withAnimation(.interpolatingSpring(duration: duration)) {
                    isOpen = true
                }
                
                PremiumHubModel.configureFor(language: language)
                timerBridge.set(hub.mainSecondsLeft, total: hub.mainRoundLength)
                
                if !UserDefaults.standard.bool(forKey: "hasSeenHubTutorial_v1") {
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await MainActor.run {
                            showTutorial = true
                        }
                    }
                } else {
                    Task {
                        try? await Task.sleep(nanoseconds: 3_300_000_000)
                        await MainActor.run {
                            hub.initLoop()
                        }
                    }
                }
            }
            .onDisappear {
                hub.hide()
            }
            .onChange(of: local.locale) {
                PremiumHubModel.configureFor(language: language)
                hub.resetAll()
                timerBridge.set(hub.mainSecondsLeft, total: hub.mainRoundLength)
            }
            .customAlert("Network error",
                         type: .fail,
                         isPresented: $showError,
                         actionText: "OK",
                         action: closeView,
                         message: { Text("something went wrong") })
            .overlay {
                if showTutorial {
                    HubTutorialOverlay {
                        UserDefaults.standard.set(true, forKey: "hasSeenHubTutorial_v1")
                        withAnimation(.easeOut(duration: 0.25)) {
                            showTutorial = false
                        }
                        
                        Task {
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            await MainActor.run {
                                hub.initLoop()
                            }
                        }
                    }
                    .transition(.opacity)
                } else if hub.showNewWordToast {
                    NewWordToast(offsetY: -60)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .zIndex(2)
                }
            }
        }
    }
    
    @ViewBuilder private func timerView(secondsLeft: Int, timer: HubTimerBridge, skipProgressAnimation: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HubGamePalette.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HubGamePalette.stroke, lineWidth: 1))
                .shadow(color: HubGamePalette.glow, radius: 7, y: 3)
            
            MainRoundTimerView(
                secondsLeft: secondsLeft,
                total: timer.total,
                identity: timer.identity,
                skipProgressAnimation: skipProgressAnimation
            )
            .frame(height: 18)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 32)
    }
}

// MARK: - Top bar
private struct BackPill: View {
    var action: () -> Void
    var body: some View { BackButton(title: "Exit" ,action: action) }
}

// 🏆 Pill (unchanged)
struct SolvedCounterPill: View {
    let count: Int
    let rank: Int?
    let onTap: () -> Void
    private enum Tier { case regular, bronze, silver, gold }
    private var tier: Tier {
        guard let r = rank else { return .regular }
        if r <= 10 { return .gold }
        if r <= 50 { return .silver }
        if r <= 100 { return .bronze }
        return .regular
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill").font(.system(size: 12, weight: .bold)).symbolRenderingMode(.hierarchical)
            Text("\(count)").font(.caption.weight(.bold)).monospacedDigit()
        }
        .foregroundStyle(Color.dynamicBlack)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(background)
        .overlay(Capsule().stroke(strokeColor.opacity(overlayA), lineWidth: 1))
        .shadow(color: shadowColor.opacity(0.35), radius: 6, y: 2)
        .accessibilityLabel("Solved words \(count)".localized)
        .onTapGesture { onTap() }
        .opacity(rank == nil ? 0 : 1)
    }
    @ViewBuilder private var background: some View {
        switch tier {
        case .regular:
            Capsule().fill(LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.3), .gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .gold:
            Capsule().fill(LinearGradient(colors: [Color(red:1,green:0.95,blue:0.70), Color(red:1,green:0.84,blue:0.0), Color(red:0.80,green:0.50,blue:0.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .silver:
            Capsule().fill(LinearGradient(colors: [Color(red:0.90,green:0.92,blue:0.95), Color(red:0.66,green:0.71,blue:0.76), Color(red:0.42,green:0.47,blue:0.52)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .bronze:
            Capsule().fill(LinearGradient(colors: [Color(hue:0.08,saturation:0.65,brightness:0.85), Color(hue:0.08,saturation:0.55,brightness:0.70), Color(hue:0.08,saturation:0.50,brightness:0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
    private var strokeColor: Color { switch tier { case .regular: return .white; case .gold: return .yellow; case .silver: return .white; case .bronze: return .orange } }
    private var shadowColor: Color { switch tier { case .regular: return .black; case .gold: return .yellow; case .silver: return .white; case .bronze: return .orange } }
    private var overlayA: CGFloat { switch tier { case .regular: return 0.15; case .gold: return 0.45; case .silver: return 0.35; case .bronze: return 0.35 } }
}

// MARK: - Palette
enum PremiumPalette {
    static let card = Color.dynamicBlack.opacity(0.06)
    static let stroke = Color.dynamicBlack.opacity(0.09)
    static let glow = Color.dynamicBlack.opacity(0.22)
    static let accent = Color.cyan
    static let accent2 = Color.mint
    static let frost = Color.dynamicWhite.opacity(0.85)
    static let sand = Color(hue: 0.10, saturation: 0.35, brightness: 0.90)
    static let wax = Color(hue: 0.10, saturation: 0.08, brightness: 0.95)
    static let sonar = Color(hue: 0.58, saturation: 0.85, brightness: 0.75)
}

// MARK: - Gold gradient (needed by MainRoundCircle)
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

// MARK: - Model

final public class PremiumHubModel: ObservableObject {
    typealias VM = PremiumHubViewModel
    // Alphabets
    private static let englishAlphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
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
    
    // Timer
    private static let staticMainRoundLength = Int(60 * 6)
    var mainRoundLength: Int { PremiumHubModel.staticMainRoundLength }
    
    @Published private(set) var slots: [MiniSlot] = []
    @Published private(set) var mainSecondsLeft: Int = PremiumHubModel.staticMainRoundLength
    @Published private(set) var gameHistory: [[String]] = []
    @Published private(set) var isPaused: Bool = false
    
    @Published var discoveredLetters: Set<Character> = []
    @Published var canInteract: Bool = true
    @Published var aiDifficulty: AIDifficulty? = nil
    @Published var solvedWords: Int = 0
    @Published var rank: Int?
    @Published var showNewWordToast = false
    
    @Published private var skipAnimationForProgress: Bool = false
    
    private var newWordTask: Task<Void, Never>?
    private var newWordAnimationTask: Task<Void, Never>?
    
    // letter preference window
    private var lastWordLetterFoundAt: Date = Date()
    private var windowSeconds: TimeInterval { Double(mainRoundLength) / 8.0 }
    
    private var tick: AnyCancellable?
    private let uniqe: String?
    
    // Provider
    private let catalog = MiniGameCatalog()
    
    private var isShown = false
    
    let vm = VM()
    
    var isSkipProgressAnimation: Bool { skipAnimationForProgress }
    
    init(uniqe: String?) {
        self.uniqe = uniqe
        self.aiDifficulty = loadAIDifficulty()
    }
    
    func show() {
        isShown = true
        if slots.isEmpty {
            slots = catalog.uniqueInitialSlots(hasAI: aiDifficulty != nil, hub: self)
        } else if aiDifficulty == nil {
            slots = slots.map { s in s.kind == .aiMerchant ? catalog.makeSlot(hasAI: false, hub: self, existing: slots) : s }
        }
    }
    
    func hide() {
        isShown = false
    }
    
    func setGameHistoryForRound(history: [[String]]) {
        gameHistory = history
    }
    
    func skipProgressAnimation() {
        skipAnimationForProgress = true
    }
    
    func pause()  { isPaused = true }
    func resume() { isPaused = false }
    func sync(time: Int) { mainSecondsLeft = time }
    
    func start() {
        guard tick == nil else { return }
        tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                // === PAUSE GUARD ===
                guard !isPaused else { return }
                
                mainSecondsLeft -= 1
                mainSecondsLeft = max(0, self.mainSecondsLeft)
                skipAnimationForProgress = false
                if mainSecondsLeft == 0 {
                    Task.detached { @MainActor [weak self] in
                        guard let self else { return }
                        guard isShown else { return }
                        resetAll()
                    }
                    return
                }
                // refresh expired, respecting cap
                let now = Date()
                let refreshed = slots.enumerated().map { (idx, s) -> MiniSlot in
                    if s.expiresAt <= now {
                        var others = self.slots; others.remove(at: idx)
                        return self.catalog.makeSlot(hasAI: self.aiDifficulty != nil, hub: self, existing: others, capPerKind: 2)
                    }
                    return s
                }
                slots = refreshed
            }
    }
    
    func initLoop() {
        guard tick == nil else { return }
        resetLoop()
    }
    
    private func resetLoop() {
        self.stop()
        self.mainSecondsLeft = self.mainRoundLength
        self.discoveredLetters = []
        self.gameHistory = []
        self.vm.word = .empty
        self.showNewWordToast = false
        self.newWordAnimation()
        self.lastWordLetterFoundAt = Date()
        if let uniqe {
            newWordTask?.cancel()
            newWordTask = Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                guard let solved = await vm.getScore(uniqe: uniqe) else { await vm.word(uniqe: uniqe); return }
                await vm.word(uniqe: uniqe)
                UserDefaults.standard.set(solved.value, forKey: "wins_count")
                UserDefaults.standard.set(solved.rank, forKey: "wins_rank")
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    start()
                    solvedWords = solved.value
                    withAnimation(.easeInOut(duration: 0.3)) { self.rank = solved.rank }
                }
            }
        }
    }
    
    private func newWordAnimation() {
        newWordAnimationTask?.cancel()
        newWordAnimationTask = Task(priority: .high) { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.showNewWordToast = true
                }
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.showNewWordToast = false
                }
            }
        }
    }
    
    func resetAll() {
        slots = catalog.uniqueInitialSlots(hasAI: aiDifficulty != nil, hub: self)
        resetLoop()
    }
    
    func stop() { newWordAnimationTask?.cancel(); newWordTask?.cancel(); tick?.cancel(); tick = nil }
    
    // Visual grid mapping
    func slot(atVisualIndex r: Int, _ c: Int) -> MiniSlot? {
        let map = [[0,1,2],[3,-1,4],[5,6,7]]
        let i = map[r][c]
        guard i >= 0, i < slots.count else { return nil }
        return slots[i]
    }
    
    func replaceSlot(_ s: MiniSlot) {
        guard let i = slots.firstIndex(of: s) else { return }
        var others = slots; others.remove(at: i)
        slots[i] = catalog.makeSlot(hasAI: aiDifficulty != nil, hub: self, existing: others, capPerKind: 2)
    }
    
    // MARK: Letter preference & picking
    private func undiscoveredAlphabetLetters() -> [Character] {
        let all = Set(Self.currentAlphabet)
        return Array(all.subtracting(discoveredLetters))
    }
    private func remainingWordLetters() -> [Character] {
        let wordUpper = vm.wordValue.uppercased()
        let wordSet = Set(wordUpper.filter { Self.isLetter($0) })
        let missing = wordSet.subtracting(discoveredLetters)
        return Array(missing)
    }
    private func shouldPreferWordLetter() -> Bool {
        guard !vm.wordValue.isEmpty else { return false }
        let missing = remainingWordLetters()
        guard !missing.isEmpty else { return false }
        return Date().timeIntervalSince(lastWordLetterFoundAt) >= windowSeconds
    }
    func pickLetterForOffer() -> Character {
        let preferWord = shouldPreferWordLetter()
        let pool = preferWord ? remainingWordLetters() : undiscoveredAlphabetLetters()
        if let choice = pool.randomElement() { return choice }
        let alt = preferWord ? undiscoveredAlphabetLetters() : remainingWordLetters()
        if let choice = alt.randomElement() { return choice }
        return Self.randomLetter()
    }
    func pickLettersForOffer(count: Int) -> [Character] {
        var set = Set<Character>()
        while set.count < count {
            set.insert(pickLetterForOffer())
            if set.count < count && set.count >= Self.currentAlphabet.count { break }
        }
        return Array(set)
    }
    func recordFoundLetter(_ ch: Character) {
        let wordU = vm.wordValue.uppercased()
        if wordU.contains(String(ch).uppercased()) { lastWordLetterFoundAt = Date() }
    }
}

// MARK: - Grid 3×3 (unchanged layout)
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

private struct NewWordToast: View {
    let offsetY: CGFloat
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(.title, design: .rounded).weight(.semibold))
            Text("New Round")
                .font(.system(.title, design: .rounded).weight(.semibold))
        }
        .padding(.horizontal, 46)
        .padding(.vertical, 42)
        .foregroundStyle(Color.dynamicBlack)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .offset(y: offsetY)
        .accessibilityLabel("New Round")
    }
}

// MARK: - Main button in the middle (unchanged + hook for post-GameView reset)
private struct MainRoundCircle: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var vm: PremiumHubViewModel
    @EnvironmentObject private var timerBridge: HubTimerBridge
    @ObservedObject var hub: PremiumHubModel
    
    @State private var shimmer = false
    @State private var ripple  = false
    
    var body: some View {
        let word = vm.wordValue
        let isReady = !word.isEmpty && word.lettersAreSubset(of: hub.discoveredLetters)
        
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            shimmer = true; ripple = true
            Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 60_000_000)
                shimmer = false; ripple = false
                try? await Task.sleep(nanoseconds: 60_000_000)
                await MainActor.run {
                    hub.pause()
                    
                    router.navigateTo(
                        .premiumGame(
                            word: vm.wordValue,
                            canBeSolved: isReady,
                            history: hub.gameHistory,
                            allowedLetters: String(hub.discoveredLetters).lowercased()
                        )
                    )
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isReady ? LinearGradient.ready : LinearGradient.notReady)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5).blur(radius: 0.4))
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
        .tint(.dynamicWhite)
        .disabled(word.isEmpty)
        .grayscale(word.isEmpty ? 1 : 0)
        .onAppear {
            PremiumCoplitionHandler.shared.onForceEndPremium = { history, reset in
                hub.skipProgressAnimation()
                
                hub.resume()
                
                let time = max(0, timerBridge.secondsLeft)
                hub.sync(time: time)
                
                if reset { hub.resetAll() }
                else if let history { hub.setGameHistoryForRound(history: history) }
            }
        }
    }
}

// MARK: - Mini slot tile
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
                    .foregroundStyle(Color.dynamicBlack.opacity(0.95))
                    .frame(height: 30)
            }
            
            Text(slot.kind.title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.dynamicBlack.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
            
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let secs = max(0, Int(slot.expiresAt.timeIntervalSince(timeline.date).rounded()))
                Text("refresh in \(secs)s")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.dynamicBlack.opacity(0.55))
            }
        }
        .padding(.horizontal ,4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PremiumPalette.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PremiumPalette.stroke, lineWidth: 1))
        )
    }
}

// MARK: - Sheet host delegates view creation to Catalog

private struct MiniGameSheet: View {
    let slot: MiniSlot
    @ObservedObject var hub: PremiumHubModel
    var onDone: (MiniResult) -> Void
    
    @State private var closed = false
    @GestureState private var handlePressed = false
    
    private let catalog = MiniGameCatalog()
    
    var body: some View {
        VStack(spacing: 16) {
            // === Grabber / indicator ===
            Capsule()
                .fill(.secondary.opacity(handlePressed ? 0.55 : 0.35))
                .frame(width: 58, height: 24)
                .padding(.top, 8)
                .contentShape(Rectangle()) // bigger hit target
                .gesture(handleGesture)    // tap or short down-drag to close
                .overlay { Image(systemName: "xmark").padding(.top, 9).font(.callout.bold()) }
                .accessibilityLabel(Text("Close"))
                .accessibilityAddTraits(.isButton)
            
            HStack {
                let timeLeft = slot.secondsLeft
                Text("Time left: \(timeLeft)s")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.dynamicWhite)
                    .padding(8)
                    .background(Capsule().fill(Color.dynamicBlack.opacity(0.82)))
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
            
            // Header
            HStack {
                Label(slot.kind.title, systemImage: slot.kind.icon)
                    .labelStyle(.titleAndIcon)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.dynamicBlack)
                Spacer()
                if slot.containsLetter {
                    Text("Contains letter")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(PremiumPalette.accent.opacity(0.22)))
                        .foregroundStyle(Color.dynamicBlack.opacity(0.9))
                } else {
                    Text("May be empty")
                        .font(.caption2)
                        .foregroundStyle(Color.dynamicBlack.opacity(0.6))
                }
            }
            .padding(.horizontal)
            
            // Mini content
            catalog.view(for: slot, hub: hub, onDone: onDone)
                .padding(.horizontal)
            
            Spacer()
        }
        .background(
            LinearGradient(colors: [Color.dynamicWhite.opacity(0.88), Color.dynamicWhite.opacity(0.94)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
        // This can stay; the presenter also disables interactive dismiss for hard-stop
        .interactiveDismissDisabled(true)
        // Keep timers / TTL
        .onChange(of: hub.mainSecondsLeft) { old, new in
            if old <= 0 && new == hub.mainRoundLength {
                close(.nothing)
            }
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            if !closed, Date() >= slot.expiresAt { close(.nothing) }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
    
    // MARK: - Handle gesture: tap or short downward pull to close
    private var handleGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($handlePressed) { _, state, _ in state = true }
            .onEnded { g in
                // close if tapped (tiny movement) or pulled down a bit
                let isTap = abs(g.translation.height) < 6 && abs(g.translation.width) < 6
                let pulledDown = g.translation.height > 16 || g.predictedEndTranslation.height > 24
                if isTap || pulledDown { close(.close) }
            }
    }
    
    private func close(_ result: MiniResult) {
        guard !closed else { return }
        closed = true
        onDone(result)
    }
}

struct PremiumBackground: View {
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        if scheme == .light {
            LinearGradient(
                colors: [
                    Color(hue: 0.64, saturation: 0.00, brightness: 1.00),
                    Color(hue: 0.64, saturation: 0.05, brightness: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [
                    Color.black, Color(hue: 0.64, saturation: 0.25, brightness: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Timer view (professional reset animation inside the view, no layout change)

struct MainRoundTimerView: View {
    let secondsLeft: Int
    let total: Int
    let identity: Int // bump only on reset
    
    var skipProgressAnimation: Bool = false
    
    @State private var pulse = false
    @State private var flashOpacity: Double = 0
    @State var enableProgressAnimation = false   // disables “0→progress” on first mount / after reset
    @State private var resetSweepActive = false
    @State private var resetSweepT: CGFloat = -0.25      // -0.25 → 1.25 across the bar
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
        let colors: [Color]
        switch phase {
        case .high: colors = [PremiumPalette.accent, PremiumPalette.accent2]
        case .mid:  colors = [Color(hue: 0.12, saturation: 0.95, brightness: 1.0), .orange]
        case .low:  colors = [.red, Color(hue: 0.0, saturation: 0.75, brightness: 0.9)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
    
    var body: some View {
        GeometryReader { geo in
            let fullW = geo.size.width
            let fullH = geo.size.height
            let w = fullW * progress
            
            ZStack(alignment: .leading) {
                // background rail
                Capsule().fill(Color.dynamicWhite.opacity(0.15))
                
                // filled bar
                Capsule()
                    .fill(barGradient)
                    .frame(width: w)
                    .scaleEffect(x: 1,
                                 y: (isCritical && !reduceMotion && pulse) ? 1.06 : 1,
                                 anchor: .center)
                    .hueRotation(.degrees(isCritical && !reduceMotion && pulse ? 5 : 0))
                    .shadow(color: isCritical ? .red.opacity(pulse ? 0.55 : 0.30) : .clear,
                            radius: isCritical ? (isFinal ? 14 : 10) : 0,
                            x: 0, y: isCritical ? 6 : 0)
                
                // reset flash (stays inside the filled width)
                Capsule()
                    .stroke(Color.dynamicBlack.opacity(flashOpacity), lineWidth: 3)
                    .frame(width: w)
                    .blendMode(.plusLighter)
                
                // reset sweep (sleek light that runs over the filled portion only)
                if resetSweepActive && !reduceMotion {
                    Rectangle()
                        .fill(
                            LinearGradient(gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.00), location: 0.00),
                                .init(color: .white.opacity(0.30), location: 0.45),
                                .init(color: .white.opacity(0.75), location: 0.50),
                                .init(color: .white.opacity(0.30), location: 0.55),
                                .init(color: .white.opacity(0.00), location: 1.00),
                            ]), startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: min(140, max(80, fullW * 0.35)), height: fullH)
                        .offset(x: (-fullW * 0.18) + resetSweepT * (w + fullW * 0.36))
                        .blendMode(.plusLighter)
                        .mask(
                            HStack(spacing: 0) { Rectangle().frame(width: w, height: fullH); Spacer(minLength: 0) }
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(
            HStack(spacing: 6) {
                Text("\(secondsLeft)s")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isCritical ? Color.dynamicBlack : Color.dynamicBlack.opacity(0.9))
                    .scaleEffect(isFinal && !reduceMotion && pulse ? 1.06 : 1.0)
                Text("round")
                    .font(.caption2)
                    .foregroundStyle(Color.dynamicBlack.opacity(0.5))
            }
                .padding(.horizontal, 6),
            alignment: .trailing
        )
        .clipShape(Capsule())
        .frame(height: 18)
        
        // progress animates only after first frame (prevents “0→progress” on mount / screen switch)
        .animation(!skipProgressAnimation && enableProgressAnimation ? .easeInOut(duration: 0.25) : nil, value: progress)
        .animation(.easeInOut(duration: 0.25), value: phase)
        
        // Critical-time pulsing
        .task(id: isCritical) {
            guard isCritical, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.22)) { pulse.toggle() }
            flashOpacity = isFinal ? 0.9 : 0.5
            withAnimation(.easeOut(duration: 0.16)) { flashOpacity = 0 }
        }
        .onChange(of: secondsLeft) { _, _ in
            guard isCritical else { return }
            withAnimation(.easeInOut(duration: 0.22)) { pulse.toggle() }
            flashOpacity = isFinal ? 0.9 : 0.5
            withAnimation(.easeOut(duration: 0.16)) { flashOpacity = 0 }
        }
        
        // Turn on progress animation after initial layout (so initial render is static-at-progress)
        .task {
            try? await Task.sleep(nanoseconds: 30_000_000)
            enableProgressAnimation = true
        }
        
        // Professional reset animation (runs when identity bumps)
        .task(id: identity) {
            // Show new seconds immediately, then play sweep without layout change
            enableProgressAnimation = false
            
            if reduceMotion {
                flashOpacity = 0.9
                withAnimation(.easeOut(duration: 0.22)) { flashOpacity = 0 }
            } else {
                resetSweepActive = true
                resetSweepT = -0.25
                flashOpacity = 0.8
                withAnimation(.easeInOut(duration: 0.65)) { resetSweepT = 1.25 }
                withAnimation(.easeOut(duration: 0.22)) { flashOpacity = 0 }
                try? await Task.sleep(nanoseconds: 660_000_000)
                resetSweepActive = false
            }
            
            enableProgressAnimation = true
        }
    }
}

// MARK: - Tutorial overlay (first-time user)

private struct HubTutorialOverlay: View {
    var dismiss: () -> Void
    var body: some View {
        ZStack {
            Color.dynamicWhite.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("How the Hub Works")
                    .font(.title3.weight(.bold))
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tap a tile to play a mini-game and collect letters.", systemImage: "square.grid.3x3")
                    Label("The center button starts the main game once you have the letters.", systemImage: "circle.grid.2x1.fill")
                    Label("Timer at the top: swipe it to reset the round.", systemImage: "timer")
                    Label("Tap the badge to view the leaderboard.", systemImage: "list.number")
                }
                .foregroundStyle(Color.dynamicBlack.opacity(0.9))
                .labelStyle(.titleAndIcon)
                Button("Got it") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(22)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
            .padding()
        }
    }
}

// MARK: - Discovered letters belt
private struct DiscoveredBeltView: View {
    let letters: [Character]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if letters.isEmpty {
                    VStack {
                        Text("No letters yet")
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.dynamicBlack.opacity(0.6))
                            .shadow(radius: 3, y: 2)
                        Spacer()
                    }
                    .frame(height: 30)
                } else {
                    ForEach(letters, id: \.self) { ch in
                        Text(String(ch))
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.dynamicBlack)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(PremiumPalette.accent))
                            .overlay(
                                Circle().stroke(.white.opacity(0.4), lineWidth: 1)
                                    .shadow(radius: 3, y: 2)
                            )
                    }
                }
            }
        }
    }
}

// MARK: - Pressed bounce style (used by MainRoundCircle)
struct PressedBounceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .shadow(radius: configuration.isPressed ? 6 : 12, y: configuration.isPressed ? 4 : 8)
            .animation(.spring(response: 0.22, dampingFraction: 0.65, blendDuration: 0.1),
                       value: configuration.isPressed)
    }
}

// MARK: - Shimmer sweep overlay (used by MainRoundCircle)
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

// MARK: - Ripple ring overlay (used by MainRoundCircle)
private struct RippleRing: View {
    @Binding var fire: Bool
    var body: some View {
        Circle()
            .strokeBorder(Color.dynamicBlack.opacity(0.65), lineWidth: 2)
            .scaleEffect(fire ? 1.45 : 0.9)
            .opacity(fire ? 0.0 : 0.8)
            .animation(.easeOut(duration: 0.06), value: fire)
            .allowsHitTesting(false)
    }
}

// MARK: - Haptics (lightTap / success / warn)
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
    let evt = CHHapticEvent(eventType: .hapticTransient, parameters: [
        .init(parameterID: .hapticIntensity, value: 0.5),
        .init(parameterID: .hapticSharpness, value: 0.2)
    ], relativeTime: 0)
    try? engine?.start()
    try? engine?.makePlayer(with: CHHapticPattern(events: [evt], parameters: [])).start(atTime: 0)
}

// MARK: - String helper (used by isReady check)
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
                }) { return false }
            }
        }
        return true
    }
}

// MARK: - iOS 17 conditional modifier
private extension View {
    @ViewBuilder func ifAvailable_iOS17<Content: View>(_ transform: (Self) -> Content) -> some View {
        if #available(iOS 17, *) { transform(self) } else { self }
    }
}
