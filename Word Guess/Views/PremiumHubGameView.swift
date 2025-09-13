//
//  PremiumHubGameView.swift
//

import SwiftUI
import Combine
import CoreHaptics

// MARK: - VM that plugs into your existing ViewModel APIs
@Observable
final class PremiumHubGameVM: ViewModel {
    private let network: Network
    private let word: String
    override var wordValue: String { word }
    
    required init(word: String) {
        self.network = Network(root: "score")
        self.word = word
    }
    
    func score(email: String) async -> Bool {
        let value: EmptyModel? = await network.send(route: "premiumScore",
                                                       parameters: ["email": email])
        
        return value != nil
    }
}

// MARK: - Hub-like palette (local to this file)
private enum HubGamePalette {
    static let card   = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.09)
    static let glow   = Color.white.opacity(0.22)
    static let accent = Color.cyan
    static let accent2 = Color.mint
}

// EN + HE alphabets (non-generic container)
private enum Alpha {
    static let enOrder: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ".lowercased())
    static let heOrder: [Character] = Array("אבגדהוזחטיכלמנסעפצקרשת")
    static let enSet = Set(enOrder)
    static let heSet = Set(heOrder)
}

// MARK: - Game

struct PremiumHubGameView<VM: PremiumHubGameVM>: View {
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var timer: HubTimerBridge
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    private let onForceEnd: ([[String]]?, Bool) -> Void
    
    // Allowed letters passed via init (supports EN + HE)
    private let allowedUpper: Set<Character>
    
    private let rows = 5
    private let difficulty: DifficultyType = .medium
    private let length: Int
    
    // Matrix & colors
    private var initilizeHistory: [[String]]
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var current: Int = 0
    @State private var vm: VM
    
    private var history: [[String]] { current > 0 ? Array(matrix.prefix(current)) : [] }
    
    // Timer mirror to drive UI updates
    @State private var secondsLeftLocal: Int = 0
    @State private var isVisible = false
    @State private var localTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // “Allowed letters” belt feedback
    @State private var invalidShakeTick: CGFloat = 0
    @State private var invalidPulse = false
    @State private var toastVisible = false
    
    // Win / Lose banners
    @State private var wins: Int = UserDefaults.standard.integer(forKey: "wins_count")
    @State private var showWinBanner = false
    @State private var showLoseBanner = false
    @State private var loseResetFlag = true  // true: reset board on close; false: keep (timeout)
    
    private var endBannerUp: Bool { showWinBanner || showLoseBanner }
    
    private var email: String? { loginHandeler.model?.email }
    
    private var isHE: Bool {
        local.locale.identifier.lowercased().hasPrefix("he")
    }
    private var scriptAlphabet: [Character] { isHE ? Alpha.heOrder : Alpha.enOrder }
    private var scriptSet: Set<Character> { isHE ? Alpha.heSet : Alpha.enSet }
    
    // MARK: Init
    
    /// - Parameters:
    ///   - allowedLetters: letters the user is allowed to type (case-insensitive).
    init(vm: VM, history: [[String]], allowedLetters: Set<Character>, onForceEnd: @escaping ([[String]]?, Bool) -> Void) {
        _vm = State(initialValue: vm)
        self.onForceEnd = onForceEnd
        self.length = vm.wordValue.count
        self.initilizeHistory = history
        _matrix = State(initialValue: Array(repeating: Array(repeating: "", count: vm.wordValue.count), count: rows))
        _colors = State(initialValue: Array(repeating: Array(repeating: .noGuess, count: vm.wordValue.count), count: rows))
        
        // Use device locale here (Environment isn’t available in init)
        let he = Locale.current.identifier.lowercased().hasPrefix("he")
        let alphaSet = he ? Alpha.heSet : Alpha.enSet
        
        let normalized = allowedLetters.map { ch in
            he ? ch : Character(String(ch).lowercased())
        }.filter { alphaSet.contains($0) }
        
        self.allowedUpper = Set(normalized)
    }
    
    // MARK: Body
    
    var body: some View {
        ZStack {
            background()
            
            VStack(spacing: 10) {
                topBar()
                
                // Compact, hub-like timer container
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(HubGamePalette.card)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(HubGamePalette.stroke, lineWidth: 1))
                        .shadow(color: HubGamePalette.glow, radius: 7, y: 3)
                    
                    MainRoundTimerView(secondsLeft: secondsLeftLocal, total: timer.total)
                        .frame(height: 14)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .frame(height: 32)
                .padding(.horizontal, 16)
                
                // Allowed letters belt (directly under timer)
                AllowedBeltView(letters: beltLetters(),
                                shakeTick: invalidShakeTick,
                                pulse: invalidPulse)
                .padding(.horizontal, 16)
                .overlay(alignment: .top) {
                    if toastVisible {
                        CapsuleToast(text: toastText)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, -6)
                    }
                }
                
                gameArea()
                    .padding(.horizontal, 12)
                    .opacity(endBannerUp ? 0.25 : 1)
                
                AppTitle(size: 50)
                    .padding(.top, UIDevice.isPad ? 100 : 80)
                    .padding(.bottom, UIDevice.isPad ? 175 : 135)
                    .shadow(radius: 4)
            }
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)
            
            if showWinBanner {
                WinCelebrationView(wins: wins) { forceEnd(asFail: false, reset: true) }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(2)
            }
            
            if showLoseBanner {
                LoseCelebrationView { forceEnd(asFail: true, reset: loseResetFlag) }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .onAppear {
            isVisible = true
            fillHistory()
            secondsLeftLocal = timer.secondsLeft
            startAmbient()
        }
        .onDisappear { isVisible = false }
        
        // Keep in sync with hub if it IS publishing (mirror wins over our local drive)
        .onReceive(timer.$secondsLeft.removeDuplicates()) { new in
            // If hub still drives, trust it.
            secondsLeftLocal = new
            guard isVisible, !endBannerUp else { return }
            // If the hub reset while we’re here, end the game as a fail.
            if new == timer.total && new > 0 { forceEnd(asFail: true, reset: false) }
        }
        .onReceive(timer.$total.removeDuplicates()) { _ in
            secondsLeftLocal = timer.secondsLeft
        }
        
        // Local fallback ticker: if hub stopped (e.g., hub view disappeared), we drive time.
        .onReceive(localTicker) { _ in
            guard isVisible, !endBannerUp else { return }
            
            // If hub already advanced this tick, just mirror it and skip.
            if timer.secondsLeft != secondsLeftLocal {
                secondsLeftLocal = timer.secondsLeft
                return
            }
            
            // Drive our own countdown and write back to the bridge.
            if secondsLeftLocal > 0 {
                secondsLeftLocal -= 1
                timer.set(secondsLeftLocal, total: timer.total)
            } else {
                // TIMEOUT → lose animation (no reset)
                loseResetFlag = false
                audio.stop()
                audio.playSound(sound: "fail", type: "wav")
                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { showLoseBanner = true }
            }
        }
    }
    
    // MARK: UI parts
    
    private var toastText: String {
        "Use allowed letters only".localized
    }
    
    @ViewBuilder private func topBar() -> some View {
        ZStack {
            HStack {
                BackButton(title: nil ,icon: "xmark",
                           action: { forceEnd(asFail: false, reset: false, withHistory: true) })
                .environment(\.colorScheme, .dark)
                .padding(.vertical, 8)
                Spacer()
            }
            
            Text("WordZap")
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(radius: 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }
    
    @ViewBuilder private func gameArea() -> some View {
        VStack(spacing: 8) {
            ForEach(0..<rows, id: \.self) { i in
                ZStack {
                    WordView(
                        cleanCells: .constant(false),
                        allowed: (effectiveAllowedLetters, invalidInputFeedback),
                        current: $current,
                        length: length,
                        word: $matrix[i],
                        gainFocus: Binding(get: { current == i && !endBannerUp }, set: { _ in }),
                        colors: $colors[i]
                    ) {
                        guard i == current, !endBannerUp else { return }
                        nextLine(i: i)
                    }
                    .disabled(current != i || endBannerUp)
                    .shadow(radius: 4)
                }
            }
        }
        .padding(.bottom, 12)
    }
    
    @ViewBuilder private func background() -> some View {
        LinearGradient(
            colors: [Color.black,
                     Color(hue: 0.64, saturation: 0.25, brightness: 0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Logic
    
    private func fillHistory() {
        for h in initilizeHistory {
            guard let i = initilizeHistory.firstIndex(of: h) else { continue }
            self.matrix[i] = h
            self.colors[i] = vm.calculateColors(with: h)
        }
        
        current = initilizeHistory.count
    }
    
    private func startAmbient() {
        if difficulty != .tutorial {
            audio.playSound(sound: "backround", type: "mp3", loop: true)
        }
    }
    
    private func forceEnd(asFail: Bool, reset: Bool, withHistory: Bool = false) {
        isVisible = false
        audio.stop()
        if asFail { audio.playSound(sound: "fail", type: "wav") }
        onForceEnd(withHistory ? history : nil, reset)
        router.navigateBack()
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
                if let email { Task(priority: .high, operation: { await vm.score(email: email) }) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    audio.playSound(sound: "success", type: "wav")
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { showWinBanner = true }
                }
            } else {
                // OUT OF TRIES → lose animation (reset after)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    loseResetFlag = true
                    audio.playSound(sound: "fail", type: "wav")
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { showLoseBanner = true }
                }
            }
        } else if i == current {
            current = i + 1
        }
    }
    
    // MARK: - Allowed letters & filtering
    
    private var effectiveAllowedLetters: Set<Character> {
        allowedUpper
    }
    
    private func beltLetters() -> [Character] {
        let set = effectiveAllowedLetters
        if !set.isEmpty, set.allSatisfy({ Alpha.heSet.contains($0) }) {
            // Sort by Hebrew alphabet order
            return set.sorted {
                (Alpha.heOrder.firstIndex(of: $0) ?? .max) < (Alpha.heOrder.firstIndex(of: $1) ?? .max)
            }
        } else {
            // Default to English order
            return set.sorted {
                (Alpha.enOrder.firstIndex(of: $0) ?? .max) < (Alpha.enOrder.firstIndex(of: $1) ?? .max)
            }
        }
    }
    
    private func invalidInputFeedback() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) {
            invalidShakeTick += 1
            invalidPulse = true
            toastVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.2)) { invalidPulse = false; toastVisible = false }
        }
    }
}

// MARK: - Allowed letters belt + feedback (hub-style)
private struct AllowedBeltView: View {
    let letters: [Character]
    var shakeTick: CGFloat
    var pulse: Bool
    var placeholder: String = "No letters yet — play minis to collect".localized
    
    var body: some View {
        Group {
            if letters.isEmpty {
                HStack(spacing: 8) {
                    // subtle placeholder chips
                    ForEach(0..<5, id: \.self) { _ in
                        Text("?")
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .foregroundStyle(.black.opacity(0.35))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(.white.opacity(0.70)))
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    }
                    Text(placeholder)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
        .modifier(Shake(animatableData: shakeTick))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(pulse ? 0.85 : 0), lineWidth: 2)
                .animation(.easeInOut(duration: 0.2), value: pulse)
        )
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
            VStack(spacing: 8) {
                Text("Wins")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
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

// MARK: - Lose Celebration (new)

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
            VStack(spacing: 8) {
                Text("Round Over".localized)
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
