//
//  PremiumHubGameView.swift
//

import SwiftUI
import Combine
import CoreHaptics

// MARK: - VM that plugs into your existing ViewModel APIs
final class PremiumHubGameVM: ViewModel {
    private let word: String
    override var wordValue: String { word }
    init(word: String) { self.word = word; super.init() }
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
    
    private let onForceEnd: () -> Void
    
    // Allowed letters passed via init (supports EN + HE)
    private let allowedUpper: Set<Character>
    
    private let rows = 5
    private let difficulty: DifficultyType = .medium
    private let length: Int
    
    // Matrix & colors
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var current: Int = 0
    @State private var vm: VM
    
    // Timer mirror to drive UI updates
    @State private var secondsLeftLocal: Int = 0
    @State private var isVisible = false
    @State private var localTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // “Allowed letters” belt feedback
    @State private var invalidShakeTick: CGFloat = 0
    @State private var invalidPulse = false
    @State private var toastVisible = false
    
    // Win banner
    @State private var wins: Int = UserDefaults.standard.integer(forKey: "wins_count")
    @State private var showWinBanner = false
    
    private var isHE: Bool {
        local.locale.identifier.lowercased().hasPrefix("he")
    }
    private var scriptAlphabet: [Character] { isHE ? Alpha.heOrder : Alpha.enOrder }
    private var scriptSet: Set<Character> { isHE ? Alpha.heSet : Alpha.enSet }
    
    // MARK: Init
    
    /// - Parameters:
    ///   - allowedLetters: letters the user is allowed to type (case-insensitive).
    init(vm: VM, onForceEnd: @escaping () -> Void, allowedLetters: Set<Character>) {
        _vm = State(initialValue: vm)
        self.onForceEnd = onForceEnd
        self.length = vm.wordValue.count
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
                
                // Compact, readable timer container
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.32))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10)))
                        .shadow(color: .black.opacity(0.20), radius: 6, y: 2)
                    
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
                    .opacity(showWinBanner ? 0.25 : 1)
                
                AppTitle(size: 50)
                    .padding(.top, UIDevice.isPad ? 100 : 80)
                    .padding(.bottom, UIDevice.isPad ? 175 : 135)
                    .shadow(radius: 4)
            }
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)
            
            if showWinBanner {
                WinCelebrationView(wins: wins) { router.navigateBack() }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .onAppear {
            isVisible = true
            secondsLeftLocal = timer.secondsLeft
            startAmbient()
            current = 0
        }
        .onDisappear { isVisible = false }
        
        // Keep in sync with hub if it IS publishing (mirror wins over our local drive)
        .onReceive(timer.$secondsLeft.removeDuplicates()) { new in
            // If hub still drives, trust it.
            secondsLeftLocal = new
            guard isVisible, !showWinBanner else { return }
            // If the hub reset while we’re here, end the game as a fail.
            if new == timer.total && new > 0 { forceEnd(asFail: true) }
        }
        .onReceive(timer.$total.removeDuplicates()) { _ in
            secondsLeftLocal = timer.secondsLeft
        }
        
        // Local fallback ticker: if hub stopped (e.g., hub view disappeared), we drive time.
        .onReceive(localTicker) { _ in
            guard isVisible, !showWinBanner else { return }
            
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
                forceEnd(asFail: true)
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
                BackButton(title: "back") { forceEnd(asFail: false) }
                    .padding(.vertical, 8)
                Spacer()
            }
            Text("WordZap").font(.title3.weight(.heavy)).shadow(radius: 4)
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
                        gainFocus: Binding(get: { current == i && !showWinBanner }, set: { _ in }),
                        colors: $colors[i]
                    ) {
                        guard i == current, !showWinBanner else { return }
                        nextLine(i: i)
                    }
                    .disabled(current != i || showWinBanner)
                    .shadow(radius: 4)
                }
            }
        }
        .padding(.bottom, 12)
    }
    
    @ViewBuilder private func background() -> some View {
        LinearGradient(colors: [.red, .yellow, .green, .blue],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        .blur(radius: 4)
        .opacity(0.1)
        .ignoresSafeArea()
    }
    
    // MARK: - Logic
    
    private func startAmbient() {
        if difficulty != .tutorial {
            audio.playSound(sound: "backround", type: "mp3", loop: true)
        }
    }
    
    private func forceEnd(asFail: Bool) {
        isVisible = false
        audio.stop()
        if asFail { audio.playSound(sound: "fail", type: "wav") }
        onForceEnd()
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
                UserDefaults.standard.set(wins, forKey: "wins_count")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    audio.playSound(sound: "success", type: "wav")
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { showWinBanner = true }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    audio.playSound(sound: "fail", type: "wav")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onForceEnd()
                    router.navigateBack()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.easeOut(duration: 0.2)) { invalidPulse = false; toastVisible = false }
        }
    }
}

// MARK: - Allowed letters belt + feedback
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
                            .background(Circle().fill(.white.opacity(0.45)))
                            .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
                    }
                    Text(placeholder)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(letters, id: \.self) { ch in
                            Text(String(ch))
                                .font(.system(.callout, design: .rounded).weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.white))
                                .overlay(Circle().stroke(.black.opacity(0.08), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
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
            .overlay(Capsule().stroke(Color.red.opacity(0.45)))
            .foregroundStyle(.primary)
            .shadow(radius: 4, y: 2)
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
