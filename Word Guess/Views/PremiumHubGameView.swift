//
//  PremiumHubGameView.swift
//

import SwiftUI
import Combine
import CoreHaptics

@Observable
final class PremiumHubGameVM: WordViewModel {
    private let network: Network
    private let word: String
    override var wordValue: String { word }
    
    required init(word: String) {
        self.network = Network(root: .score)
        self.word = word
    }
    
    @discardableResult
    func score(uniqe: String) async -> Bool {
        let value: EmptyModel? = await network.send(route: .premiumScore,
                                                    parameters: ["uniqe": uniqe])
        return value != nil
    }
}

private enum Alpha {
    static let enOrder: [Character] = Array("abcdefghijklmnopqrstuvwxyz")
    static let heOrder: [Character] = Array("אבגדהוזחטיכלמנסעפצקרשת")
    static let enSet = Set(enOrder)
    static let heSet = Set(heOrder)
}

struct PremiumHubGameView<VM: PremiumHubGameVM>: View {
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var timer: HubTimerBridge
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    private let onForceEnd: ([[String]]?, Bool) -> Void
    
    private let allowedUpper: Set<Character>
    
    private let rows = 5
    private let length: Int
    
    // Guess history
    private var initilizeHistory: [[String]]
    
    // Open/Close
    private let canBeSolved: Bool
    private let openDuration: Double = 0.4
    private let closeDuration: Double = 0.4
    
    private let keyboardHeightStore: KeyboardHeightStore
    
    @State private var reveld = false
    @State private var isClosing = false
    
    // Table
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var current: Int = 0
    
    // VM
    @State private var vm: VM
    
    private var history: [[String]] { current > 0 ? Array(matrix.prefix(current)) : [] }
    
    // Timer mirror
    @State private var secondsLeftLocal: Int = 0
    @State private var isVisible = false
    @State private var localTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var localTickerCancellable: AnyCancellable?
    
    @State private var invalidPulse = false
    @State private var toastVisible = false
    
    @State private var wins: Int = UserDefaults.standard.integer(forKey: "wins_count")
    @State private var rank: Int = UserDefaults.standard.integer(forKey: "wins_rank")
    @State private var showWinBanner = false
    @State private var showLoseBanner = false
    @State private var loseResetFlag = true
    
    private var endBannerUp: Bool { showWinBanner || showLoseBanner }
    private var uniqe: String? { loginHandeler.model?.uniqe }
    private var isHE: Bool { local.locale.identifier.lowercased().hasPrefix("he") }
    private var scriptAlphabet: [Character] { isHE ? Alpha.heOrder : Alpha.enOrder }
    private var scriptSet: Set<Character> { isHE ? Alpha.heSet : Alpha.enSet }
    private var toastText: String { "Use allowed letters only".localized }
    
    init(vm: VM,canBeSolved: Bool, history: [[String]], allowedLetters: Set<Character>, onForceEnd: @escaping ([[String]]?, Bool) -> Void) {
        _vm = State(initialValue: vm)
        self.onForceEnd = onForceEnd
        self.length = vm.wordValue.count
        self.initilizeHistory = history
        self.canBeSolved = canBeSolved
        self.keyboardHeightStore = .init()
        
        var seedMatrix = Array(repeating: Array(repeating: "", count: vm.wordValue.count), count: rows)
        var seedColors = Array(repeating: Array(repeating: CharColor.noGuess, count: vm.wordValue.count), count: rows)
        for (rowIdx, guess) in history.enumerated() {
            seedMatrix[rowIdx] = guess
            seedColors[rowIdx] = vm.calculateColors(with: guess)
        }
        _matrix = State(initialValue: seedMatrix)
        _colors = State(initialValue: seedColors)
        _current = State(initialValue: history.count)
        
        let he = Locale.current.identifier.lowercased().hasPrefix("he")
        let alphaSet = he ? Alpha.heSet : Alpha.enSet
        let normalized = allowedLetters
            .map { he ? $0 : Character(String($0).lowercased()) }
            .filter { alphaSet.contains($0) }
        self.allowedUpper = Set(normalized)
    }
    
    var body: some View {
        CircularRevealGate(isClosing: $isClosing, isDone: $reveld, openDuration: openDuration, closeDuration: closeDuration) {
            contant()
                .onAppear {
                    isVisible = true
                    withTransaction(Transaction(animation: nil)) {
                        secondsLeftLocal = max(0, timer.secondsLeft)
                    }
                    startAmbient()
                    
                    // Ensure only a single local ticker subscription and cancel on disappear
                    localTickerCancellable?.cancel()
                    localTickerCancellable = localTicker
                        .sink { _ in
                            guard isVisible, !endBannerUp else { return }
                            if timer.secondsLeft != secondsLeftLocal {
                                secondsLeftLocal = max(0, timer.secondsLeft)
                                return
                            }
                            if secondsLeftLocal > 0 {
                                secondsLeftLocal -= 1
                                secondsLeftLocal = max(0, secondsLeftLocal)
                                timer.set(secondsLeftLocal, total: timer.total)
                            } else {
                                loseResetFlag = false
                                audio.stop()
                                audio.playSound(sound: "fail", type: "wav")
                                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { showLoseBanner = true }
                            }
                        }
                }
                .onDisappear {
                    isVisible = false
                    audio.stop()
                    UIApplication.shared.hideKeyboard()
                    localTickerCancellable?.cancel()
                    localTickerCancellable = nil
                    secondsLeftLocal = max(0, secondsLeftLocal)
                    timer.set(secondsLeftLocal, total: timer.total)
                }
                .onReceive(timer.$secondsLeft.removeDuplicates()) { new in
                    secondsLeftLocal = max(0, new)
                }
                .onReceive(timer.$total.removeDuplicates()) { _ in
                    secondsLeftLocal = max(0, timer.secondsLeft)
                }
                .toolbar {
                    ToolbarItem(placement: .keyboard) {
                        AllowedBeltView(
                            letters: beltLetters(),
                            pulse: invalidPulse
                        )
                        .overlay {
                            if toastVisible {
                                CapsuleToast(text: toastText)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .background(.ultraThinMaterial)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 30)
                    }
                }
        }
    }
    
    @ViewBuilder private func contant() -> some View {
        GeometryReader { _ in
            background()
            ZStack {
                game()
                    .frame(maxHeight: .infinity)
                
                if showWinBanner {
                    WinCelebrationView(wins: wins) { forceEnd(reset: true) }
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(2)
                }
                
                if showLoseBanner {
                    LoseCelebrationView { forceEnd(reset: loseResetFlag) }
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(2)
                }
            }
        }
        .ignoresSafeArea(.keyboard)
    }
    
    @ViewBuilder private func game() -> some View {
        ZStack(alignment: .topLeading) { gameBody() }
    }
    
    @ViewBuilder private func gameBody() -> some View {
        VStack(spacing: 8) {
            gameTopView()
            gameTable()
            gameBottom()
        }
        .frame(maxHeight: .infinity)
    }
    
    @ViewBuilder private func gameTopView() -> some View {
        HStack(spacing: 12) {
            BackButton(title: "Close" ,
                       icon: "xmark",
                       action: { forceEnd(reset: false, withHistory: true) })
            .padding(.trailing, 11)
            
            SolvedCounterPill(count: wins, rank: rank, onTap: {})
            
            timerView()
                .padding(.trailing, 10)
        }
        .padding(.top, 4)
    }
    
    @ViewBuilder private func gameBottom() -> some View {
        ZStack {
            KeyboardHeightView(adjustBy: 43)
            AppTitle(size: 50)
                .shadow(color: .black.opacity(0.12), radius: 4, x: 4, y: 4)
                .shadow(color: .white.opacity(0.12), radius: 4, x: -4 ,y: -4)
        }
    }
    
    @ViewBuilder private func timerView() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HubGamePalette.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HubGamePalette.stroke, lineWidth: 1))
                .shadow(color: HubGamePalette.glow, radius: 7, y: 3)
            
            MainRoundTimerView(
                secondsLeft: secondsLeftLocal,
                total: timer.total,
                identity: timer.identity,
                skipProgressAnimation: true
            )
            .frame(height: 18)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 32)
    }
    
    @ViewBuilder private func gameTable() -> some View {
        VStack(spacing: 8) {
            ForEach(0..<rows, id: \.self) { i in
                WordView(
                    cleanCells: .constant(false),
                    allowed: (effectiveAllowedLetters, invalidInputFeedback),
                    current: $current,
                    length: length,
                    word: $matrix[i],
                    gainFocus: Binding(get: { current == i && !endBannerUp && reveld }, set: { _ in }),
                    colors: $colors[i]
                ) {
                    guard i == current, !endBannerUp else { return }
                    nextLine(i: i)
                }
                .opacity(current == i ? 1 : 0.9)
                .allowsHitTesting(current == i && !endBannerUp)
                .disabled(current != i || endBannerUp)
                .shadow(radius: 4)
                .opacity(keyboardHeightStore.height == 0 ? 0 : 1)
                .animation(.easeIn(duration: 0.01), value: keyboardHeightStore.height)
            }
        }
        .opacity(endBannerUp ? 0.25 : 1)
        .padding(.horizontal, 10)
    }
    
    @ViewBuilder private func background() -> some View {
        PremiumBackground()
            .ignoresSafeArea()
    }
    
    private func startAmbient() {
        audio.playSound(sound: "backround", type: "mp3", loop: true, volume: 0.24)
    }
    
    private func forceEnd(reset: Bool, withHistory: Bool = false) {
        isVisible = false
        audio.stop()
        UIApplication.shared.hideKeyboard()
        isClosing = true
        localTickerCancellable?.cancel()
        localTickerCancellable = nil
        secondsLeftLocal = max(0, secondsLeftLocal)
        timer.set(secondsLeftLocal, total: timer.total)
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDuration) {
            onForceEnd(withHistory ? history : nil, reset)
            router.navigateBack()
        }
    }
    
    private func nextLine(i: Int) {
        colors[i] = vm.calculateColors(with: matrix[i])
        
        let guess = matrix[i].joined()
        let correct = guess.lowercased() == vm.wordValue.lowercased()
        
        if correct || i == rows - 1 {
            current = .max
            audio.stop()
            
            if correct {
                wins += 1
                if let uniqe { Task.detached(priority: .high, operation: { await vm.score(uniqe: uniqe) }) }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard isVisible else { return }
                    audio.playSound(sound: "success", type: "wav")
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { showWinBanner = true }
                }
            } else {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard isVisible else { return }
                    loseResetFlag = true
                    audio.playSound(sound: "fail", type: "wav")
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { showLoseBanner = true }
                }
            }
        } else if i == current {
            current = i + 1
        }
    }
    
    private var effectiveAllowedLetters: Set<Character> {
        allowedUpper
    }
    
    private func beltLetters() -> [Character] {
        let set = effectiveAllowedLetters
        if !set.isEmpty, set.allSatisfy({ Alpha.heSet.contains($0) }) {
            return set.sorted {
                (Alpha.heOrder.firstIndex(of: $0) ?? .max) < (Alpha.heOrder.firstIndex(of: $1) ?? .max)
            }
        } else {
            return set.sorted {
                (Alpha.enOrder.firstIndex(of: $0) ?? .max) < (Alpha.enOrder.firstIndex(of: $1) ?? .max)
            }
        }
    }
    
    private func invalidInputFeedback() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
            invalidPulse = true
            toastVisible = true
        }
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard isVisible else { return }
            withAnimation(.easeOut(duration: 0.25)) { invalidPulse = false }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard isVisible else { return }
            withAnimation(.easeOut(duration: 0.20)) { toastVisible = false }
        }
    }
}

// MARK: - Allowed letters belt + feedback (hub-style)
private struct AllowedBeltView: View {
    let letters: [Character]
    var pulse: Bool
    var placeholder: String = "No letters yet — play minis to collect"
    
    @State private var sweepKey = UUID() // restart sweep per pulse
    
    var body: some View {
        Group {
            if letters.isEmpty {
                HStack(spacing: 10) {
                    ForEach(0..<5, id: \.self) { _ in
                        Text("?")
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .foregroundStyle(.black.opacity(0.35))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(.white.opacity(0.70)))
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    }
                    Text(placeholder.localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(letters, id: \.self) { ch in
                            Text(String(ch.uppercased()))
                                .font(.system(.callout, design: .rounded).weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(HubGamePalette.accent))
                                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(HubGamePalette.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HubGamePalette.stroke, lineWidth: 1))
                .shadow(color: HubGamePalette.glow, radius: 6, y: 2)
        )
        // polished invalid feedback:
        .overlay {
            if pulse {
                InvalidSweepOverlay().id(sweepKey)
            }
        }
        .overlay(
            // soft inner glow instead of a harsh border
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(pulse ? 0.16 : 0))
                .padding(1)
                .animation(.easeInOut(duration: 0.22), value: pulse)
        )
        .overlay(
            // subtle outer rim when pulsing
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(pulse ? 0.55 : 0), lineWidth: 1.5)
                .blur(radius: pulse ? 0.5 : 0)
                .animation(.easeInOut(duration: 0.22), value: pulse)
        )
        .scaleEffect(pulse ? 1.02 : 1.0)
        .modifier(Shake(travel: 0.2, animatableData: pulse ? 1 : 0)) // you already have Shake in this file
        .onChange(of: pulse) { old, new in
            if new { sweepKey = UUID() } // restart sweep each time
        }
    }
}

// one-shot red sweep, runs once per pulse
private struct InvalidSweepOverlay: View {
    @State private var x: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: .clear,                location: 0.00),
                        .init(color: .red.opacity(0.22),    location: 0.42),
                        .init(color: .red.opacity(0.55),    location: 0.50),
                        .init(color: .red.opacity(0.22),    location: 0.58),
                        .init(color: .clear,                location: 1.00),
                    ]), startPoint: .top, endPoint: .bottom)
                )
                .frame(width: geo.size.width * 0.90)
                .offset(x: x * geo.size.width)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.45)) { x = 1.2 }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Small helpers

private struct CapsuleToast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15)))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

private struct Shake: GeometryEffect {
    var travel: CGFloat = 7
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = travel * sin(animatableData * .pi * 2)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

// MARK: - Win Celebration (unchanged)

private struct WinCelebrationView: View {
    let wins: Int
    var onDone: () -> Void
    
    @State private var scale: CGFloat = 0.6
    @State private var ringOpacity: CGFloat = 0.8
    @State private var ringScale: CGFloat = 0.6
    @State private var shimmerPhase: CGFloat = 0
    @State private var confettiFall: Bool = false
    
    private let duration: Double = 2.8
    
    var body: some View {
        ZStack {
            ConfettiLayer(active: confettiFall).allowsHitTesting(false)
            ZStack {
                Circle()
                    .strokeBorder(AngularGradient(colors: [.yellow, .green, .cyan, .yellow], center: .center),
                                  lineWidth: 3)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                Text("\(wins)")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        AngularGradient(colors: [.yellow, .green, .mint, .cyan, .yellow],
                                        center: .center,
                                        angle: .degrees(Double(shimmerPhase) * 360))
                    )
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.2)))
                    .scaleEffect(scale)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
            .padding(.top, 8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { scale = 1.48 }
            withAnimation(.easeOut(duration: 0.9)) { ringScale = 1.85; ringOpacity = 0.0 }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) { shimmerPhase = 1 }
            withAnimation(.easeOut(duration: 0.6)) { confettiFall = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { onDone() }
        }
    }
}

private struct ConfettiLayer: View {
    let active: Bool
    @State private var seeds: [ConfettiSeed] = (0..<22).map { _ in ConfettiSeed.random() }
    var body: some View {
        GeometryReader { geo in
            ZStack { ForEach(seeds) { ConfettiPiece(seed: $0, size: geo.size, active: active) } }
        }
        .frame(height: 140)
    }
}

private struct ConfettiSeed: Identifiable {
    let id = UUID()
    let x: CGFloat
    let delay: Double
    let speed: Double
    let rotation: Double
    let symbol: String
    let color: Color
    static func random() -> ConfettiSeed {
        let symbols = ["✨","★","✦","✧","•"]
        let colors: [Color] = [.yellow, .mint, .cyan, .orange, .white]
        return .init(x: .random(in: 0.05...0.95),
                     delay: .random(in: 0...0.35),
                     speed: .random(in: 0.8...1.4),
                     rotation: .random(in: -60...60),
                     symbol: symbols.randomElement()!,
                     color: colors.randomElement()!)
    }
}

private struct ConfettiPiece: View {
    let seed: ConfettiSeed
    let size: CGSize
    let active: Bool
    @State private var y: CGFloat = -20
    @State private var rot: Double = 0
    var body: some View {
        Text(seed.symbol)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(seed.color.opacity(0.9))
            .rotationEffect(.degrees(rot))
            .position(x: seed.x * size.width, y: y)
            .onAppear {
                guard active else { return }
                withAnimation(.easeIn(duration: seed.speed)) { y = 120 }
                withAnimation(.linear(duration: seed.speed)) { rot = seed.rotation }
            }
    }
}

// MARK: - Lose Celebration

private struct LoseCelebrationView: View {
    var onDone: () -> Void
    
    @State private var scale: CGFloat = 1.6
    @State private var ringOpacity: CGFloat = 0.9
    @State private var ringScale: CGFloat = 0.7
    @State private var shimmerPhase: CGFloat = 0
    @State private var debrisFall: Bool = false
    
    private let duration: Double = 2.8
    
    var body: some View {
        ZStack {
            DebrisLayer(active: debrisFall).allowsHitTesting(false)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.75))
            ZStack {
                Circle()
                    .strokeBorder(AngularGradient(colors: [.red, .orange, .pink, .red], center: .center),
                                  lineWidth: 3)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                Text("×")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        AngularGradient(colors: [.red, .orange, .pink, .red],
                                        center: .center,
                                        angle: .degrees(Double(shimmerPhase) * 360))
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.18)))
                    .scaleEffect(scale)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
            .padding(.top, 8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) { scale = 1.0 }
            withAnimation(.easeOut(duration: 0.85)) { ringScale = 1.9; ringOpacity = 0.0 }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) { shimmerPhase = 1 }
            withAnimation(.easeOut(duration: 0.55)) { debrisFall = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { onDone() }
        }
    }
}

private struct DebrisLayer: View {
    let active: Bool
    @State private var seeds: [DebrisSeed] = (0..<22).map { _ in DebrisSeed.random() }
    var body: some View {
        GeometryReader { geo in
            ZStack { ForEach(seeds) { DebrisPiece(seed: $0, size: geo.size, active: active) } }
        }
        .frame(height: 140)
    }
}

private struct DebrisSeed: Identifiable {
    let id = UUID()
    let x: CGFloat
    let delay: Double
    let speed: Double
    let rotation: Double
    let symbol: String
    let color: Color
    static func random() -> DebrisSeed {
        let symbols = ["✖︎","•","—","·"]
        let colors: [Color] = [.red, .orange, .pink, .white.opacity(0.9)]
        return .init(x: .random(in: 0.05...0.95),
                     delay: .random(in: 0...0.25),
                     speed: .random(in: 0.7...1.2),
                     rotation: .random(in: -80...80),
                     symbol: symbols.randomElement()!,
                     color: colors.randomElement()!)
    }
}

private struct DebrisPiece: View {
    let seed: DebrisSeed
    let size: CGSize
    let active: Bool
    @State private var y: CGFloat = -18
    @State private var rot: Double = 0
    var body: some View {
        Text(seed.symbol)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(seed.color.opacity(0.85))
            .rotationEffect(.degrees(rot))
            .position(x: seed.x * size.width, y: y)
            .onAppear {
                guard active else { return }
                withAnimation(.easeIn(duration: seed.speed)) { y = 120 }
                withAnimation(.linear(duration: seed.speed)) { rot = seed.rotation }
            }
    }
}

struct CircularRevealGate<Content: View>: View {
    @Binding var isClosing: Bool
    @Binding var isDone: Bool
    
    private let openDuration: Double
    private let closeDuration: Double
    
    @State private var progress: CGFloat = 0.0
    
    let content: Content
    
    init(isClosing: Binding<Bool>, isDone: Binding<Bool>,
         openDuration: Double = 0.35, closeDuration: Double = 0.35,
         @ViewBuilder content: () -> Content) {
        self._isClosing = isClosing
        self._isDone = isDone
        self.openDuration = openDuration
        self.closeDuration = closeDuration
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { _ in
            let size = UIScreen.main.bounds
            let w = size.width
            let h = size.height
            let diag = sqrt(w*w + h*h)
            
            PremiumBackground()
                .ignoresSafeArea()
            
            content
                .mask(
                    Circle()
                        .frame(width: progress * diag * 2,
                               height: progress * diag * 2)
                        .position(x: w/2, y: h/2)
                        .offset(y: -h * 0.14)
                )
                .onAppear {
                    progress = 0
                    withAnimation(.easeOut(duration: openDuration)) {
                        progress = 1
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + openDuration) {
                        isDone = true
                    }
                }
                .onChange(of: isClosing) { _, closing in
                    guard closing else { return }
                    withAnimation(.easeIn(duration: closeDuration)) {
                        progress = 0
                    }
                }
        }
    }
}

