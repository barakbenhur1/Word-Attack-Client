//
//  ContentView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI
import CoreData
import Combine

// MARK: - Text Theme Helpers

private enum TextTone { case primary, secondary, tertiary, accent }

private extension View {
    @inline(__always)
    func themedText(_ tone: TextTone) -> some View {
        switch tone {
        case .primary:   return self.foregroundStyle(.white)                // crisp white
        case .secondary: return self.foregroundStyle(.white.opacity(0.78))  // soft white
        case .tertiary:  return self.foregroundStyle(.white.opacity(0.58))  // dimmer white
        case .accent:    return self.foregroundStyle(Color(red: 0.98, green: 0.85, blue: 0.37)) // soft gold
        }
    }
    @inline(__always)
    func softTextShadow() -> some View {
        shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
    }
}

struct GameView<VM: DifficultyWordViewModel>: View {
    @EnvironmentObject private var coreData: PersistenceController
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var premium: PremiumManager
    @EnvironmentObject private var session: GameSessionManager
    
    private let queue = DispatchQueue.main
    private let rows: Int = 5
    private let diffculty: DifficultyType
    private var length: Int { return diffculty.getLength() }
    private var uniqe: String? { return loginHandeler.model?.uniqe }
    
    private let keyboardHeightStore: KeyboardHeightStore
    
    private typealias ScoreAnimationParams = (value: Int, opticity: CGFloat, scale: CGFloat, offset: CGFloat)

    @State private var interstitialAdManager: InterstitialAdsManager?
    @State private var current: Int
    @State private var scoreAnimation: ScoreAnimationParams
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var vm = VM()
    
    @State private var didStart: Bool
    @State private var timeAttackAnimation: Bool
    @State private var timeAttackAnimationDone: Bool
    @State private var endFetchAnimation: Bool
    @State private var showError: Bool
    
    @State private var cleanCells: Bool
    
    // Task/cancel management
    @State private var isVisible: Bool
    
    private func guardVisible() -> Bool { isVisible && !Task.isCancelled }
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    private func handleError() {
        guard vm.isError else { return }
        showError = true
    }
    
    private func closeAfterError() {
        navBack()
    }
    
    private func handleWordChange() {
        guard vm.word != .empty else { return }
        initMatrixState()
        
        switch diffculty {
        case .tutorial, .ai: break
        default: Task(priority: .utility) { await SharedStore.writeDifficultyStatsAsync(.init(answers: vm.word.number, score: vm.score), for: diffculty.liveValue) }
        }
        
        guard interstitialAdManager == nil || !interstitialAdManager!.shouldShowInterstitial(for: vm.word.number) else { interstitialAdManager?.loadInterstitialAd(); return }
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000)
            initalConfigirationForWord()
            handleTimeAttackIfNeeded()
        }
    }
    
    private func handleInterstitial() {
        guard let interstitialAdManager = interstitialAdManager, interstitialAdManager.interstitialAdLoaded else { return }
        interstitialAdManager.displayInterstitialAd {
            initalConfigirationForWord()
            handleTimeAttackIfNeeded()
        }
    }
    
    private func handleTimeAttackIfNeeded() {
        guard interstitialAdManager == nil || !interstitialAdManager!.interstitialAdLoaded else { return }
        switch diffculty {
        case .tutorial: break
        default:
            guard endFetchAnimation && vm.word.isTimeAttack else { return }
            timeAttackAnimationDone = false
            withAnimation(.interpolatingSpring(.smooth)) { timeAttackAnimation = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard guardVisible() else { return }
                await MainActor.run {
                    timeAttackAnimation = false
                    timeAttackAnimationDone = true
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard guardVisible() else { return }
                audio.playSound(sound: "tick",
                                type: "wav",
                                loop: true)
            }
        }
    }
    
    private func handleGuessworkChage() {
        let guesswork = vm.word.word.guesswork
        for i in 0..<guesswork.count {
            for j in 0..<guesswork[i].count { matrix[i][j] = guesswork[i][j] }
            colors[i] = vm.calculateColors(with: matrix[i])
        }
        
        guard interstitialAdManager == nil || !interstitialAdManager!.shouldShowInterstitial(for: vm.word.number) else { return }
        guard vm.word.isTimeAttack else { return }
        current = guesswork.count
    }
    
    private func onAppear(uniqe: String) {
        guard !didStart && (interstitialAdManager == nil || !interstitialAdManager!.initialInterstitialAdLoaded) else { return }
        switch diffculty {
        case .tutorial: coreData.new()
        default: session.startNewRound(id: diffculty)
        }
        interstitialAdManager = AdProvider.interstitialAdsManager(id: "GameInterstitial")
        if let interstitialAdManager, diffculty != .tutorial {
            interstitialAdManager.displayInitialInterstitialAd {
                guard guardVisible() else { return }
                Task.detached(priority: .userInitiated) {
                    await handleNewWord(uniqe: uniqe)
                    await MainActor.run {
                        endFetchAnimation = true
                        didStart = vm.word != .empty
                    }
                }
            }
        } else {
            Task.detached(priority: .userInitiated) {
                await handleNewWord(uniqe: uniqe)
                await MainActor.run {
                    endFetchAnimation = true
                    didStart = vm.word != .empty
                }
            }
        }
    }
    
    private func handleNewWord(uniqe: String) async {
        await vm.getScore(diffculty: diffculty, uniqe: uniqe)
        await vm.word(diffculty: diffculty, uniqe: uniqe)
    }
    
    init(diffculty: DifficultyType) {
        self.diffculty = diffculty
        
        self.matrix = [[String]](repeating: [String](repeating: "",
                                                     count: diffculty.getLength()),
                                 count: rows)
        self.colors = [[CharColor]](repeating: [CharColor](repeating: .noGuess,
                                                           count: diffculty.getLength()),
                                    count: rows)
        
        self.keyboardHeightStore = .init()
        self.didStart = false
        self.timeAttackAnimation = false
        self.timeAttackAnimationDone = true
        self.endFetchAnimation = false
        self.showError = false
        self.cleanCells = false
        self.isVisible = false
        self.scoreAnimation = (0, CGFloat(0), CGFloat(0), CGFloat(30))
        self.current = 0
    }
    
    var body: some View {
        conatnet()
            .ignoresSafeArea(.keyboard)
            .onAppear { isVisible = true }
            .onDisappear {
                isVisible = false
                audio.stop()
                // cancel outstanding tasks
                scoreAnimation = (0, CGFloat(0), CGFloat(0), CGFloat(30))
            }
            .customAlert("Network error",
                         type: .fail,
                         isPresented: $showError,
                         actionText: "OK",
                         action: closeAfterError,
                         message: { Text("something went wrong") })
    }
    
    @ViewBuilder private func conatnet() -> some View {
        GeometryReader { proxy in
            background()
            ZStack(alignment: .top) {
                topBar()
                    .padding(.top, 4)
                game()
                    .padding(.top, 5)
                overlayViews(proxy: proxy)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: interstitialAdManager?.interstitialAdLoaded, handleInterstitial)
    }
    
    
    @ViewBuilder private func topBar() -> some View {
        HStack {
            backButton()
            Spacer()
            AdProvider.adView(id: "GameBanner", withPlaceholder: true)
                .frame(minHeight: 40, maxHeight: 40)
                .background(.ultraThinMaterial.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            Spacer()
        }
    }
    
    @ViewBuilder private func background() -> some View {
        GameViewBackground()
            .ignoresSafeArea()
    }
    
    @ViewBuilder private func tutorialTop() -> some View {
        VStack {
            // Title
            Text("Tutorial")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .softTextShadow()
            
            // Subtitle / hint
            let attr: AttributedString = {
                if current < 3 || current == .max {
                    var a = AttributedString("Guess The 4 Letters Word".localized)
                    a.foregroundColor = Color.dynamicBlack.opacity(0.85)
                    return a
                } else {
                    let theWord = vm.wordValue
                    var a = AttributedString("\("the word is".localized) \"\(theWord)\" \("try it, or not ;)".localized)")
                    let range = a.range(of: theWord)!
                    a.foregroundColor = Color.dynamicBlack.opacity(0.8)
                    a[range].foregroundColor = .orange
                    return a
                }
            }()
            
            Text(attr)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .softTextShadow()
        }
        .padding()
    }
    
    @ViewBuilder private func gameTable() -> some View {
        ForEach(0..<rows, id: \.self) { i in
            ZStack {
                let gainFocus = Binding(get: { current == i && endFetchAnimation && timeAttackAnimationDone },
                                        set: { _ in })
                WordView(cleanCells: $cleanCells,
                         current: $current,
                         length: length,
                         word: $matrix[i],
                         gainFocus: gainFocus,
                         colors: $colors[i]) {
                    guard i == current else { return }
                    nextLine(i: i)
                }
                         .disabled(current != i)
                         .shadow(radius: 4)
                
                if vm.word.isTimeAttack && timeAttackAnimationDone && current == i {
                    let start = Date()
                    let end = start.addingTimeInterval(diffculty == .easy ? 20 : 15)
                    ProgressBarView(
                        length: length,
                        value: 0,
                        total: end.timeIntervalSinceNow - start.timeIntervalSinceNow,
                        done: { nextLine(i: i) }
                    )
                    .opacity(0.2)
                }
            }
            .opacity(diffculty == .tutorial && keyboardHeightStore.height == 0 ? 0 : 1)
            .animation(.easeIn(duration: 0.01), value: keyboardHeightStore.height)
        }
    }
    
    @ViewBuilder private func gameTopView() -> some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .top) {
                switch diffculty {
                case .tutorial: tutorialTop()
                default:        gameTop()
                }
            }
            .shadow(radius: 4)
        }
        .padding(.bottom, -10)
    }
    
    @ViewBuilder private func gameTop() -> some View {
        ZStack(alignment: .trailing) {
            HStack {
                VStack {
                    Spacer()
                    Text(diffculty.stringValue)
                        .multilineTextAlignment(.center)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .softTextShadow()
                        .padding(.bottom, 8)
                        .padding(.leading, 10)
                }
                
                Spacer()
                
                // Center: Score
                VStack {
                    Text("Score")
                        .multilineTextAlignment(.center)
                        .font(.system(.headline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.dynamicBlack.opacity(0.78))
                        .softTextShadow()
                        .padding(.top, 5)
                    
                    ZStack(alignment: .top) {
                        Text("\(vm.score)")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(
                                .angularGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.85, blue: 0.37), // Soft gold
                                        Color(red: 0.85, green: 0.65, blue: 0.18), // Rich amber
                                        Color(red: 0.98, green: 0.85, blue: 0.42), // Soft gold
                                        Color(red: 0.85, green: 0.65, blue: 0.22), // Rich amber
                                        Color(red: 0.98, green: 0.85, blue: 0.37), // Soft gold
                                    ],
                                    center: .center,
                                    startAngle: .zero,
                                    endAngle: .degrees(360)
                                )
                            )
                            .softTextShadow()
                        
                        let value = vm.word.isTimeAttack ? scoreAnimation.value / 2 : scoreAnimation.value
                        let color: Color = value == 0 ? .red : value < 80 ? .yellow : .green
                        
                        Text("+ \(scoreAnimation.value)")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(color)
                            .opacity(scoreAnimation.opticity)
                            .scaleEffect(.init(width: scoreAnimation.scale,
                                               height: scoreAnimation.scale))
                            .offset(x: scoreAnimation.scale > 0 ? language == "he" ? 12 : -12 : 0,
                                    y: scoreAnimation.offset)
                            .blur(radius: 0.5)
                            .fixedSize()
                            .softTextShadow()
                    }
                }
                .padding(.top, -10)
                .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                VStack {
                    Spacer()
                    Text("words: \(vm.word.number)")
                        .multilineTextAlignment(.center)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .softTextShadow()
                        .padding(.bottom, 8)
                        .padding(.trailing, 10)
                }
            }
        }
        .padding(.vertical)
    }
    
    @ViewBuilder private func gameBottom() -> some View {
        ZStack {
            KeyboardHeightView()
            AppTitle(size: 50)
                .shadow(color: .black.opacity(0.12), radius: 4, x: 4, y: 4)
                .shadow(color: .white.opacity(0.12), radius: 4, x: -4 ,y: -4)
        }
    }
    
    @ViewBuilder private func gameBody() -> some View {
        VStack(spacing: 8) {
            gameTopView()
            gameTable()
            gameBottom()
            
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .ignoresSafeArea(.keyboard)
    }
    
    @ViewBuilder private func game() -> some View {
        if let uniqe {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) { gameBody() }
                    .ignoresSafeArea(.keyboard)
                    .onChange(of: vm.isError, handleError)
                    .onChange(of: vm.word.word, handleWordChange)
                    .onChange(of: vm.word.word.guesswork, handleGuessworkChage)
                    .onAppear { onAppear(uniqe: uniqe) }
                    .disabled(!endFetchAnimation || !didStart || vm.isError)
                    .opacity(endFetchAnimation && didStart && !vm.isError ? 1 : 0.7)
                    .grayscale(endFetchAnimation && didStart && !vm.isError ? 0 : 1)
            }
            .padding(.top, 44)
        }
    }
    
    private func initalConfigirationForWord() {
        switch diffculty {
        case .tutorial: break
        default: audio.playSound(sound: "backround",
                                 type: "mp3",
                                 loop: true)
        }
        current = vm.word.word.guesswork.count
    }
    
    @ViewBuilder private func overlayViews(proxy: GeometryProxy) -> some View {
        if endFetchAnimation && vm.word.isTimeAttack { timeAttackView(proxy: proxy) }
    }
    
    @ViewBuilder private func timeAttackView(proxy: GeometryProxy) -> some View {
        VStack {
            Spacer()
            Image("clock")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .frame(width: 80)
                .padding(.bottom, 10)
            Text("Time Attack")
                .font(.largeTitle)
                .softTextShadow()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            Text("double points")
                .font(.title)
                .themedText(.secondary)
                .softTextShadow()
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .scaleEffect(.init(1.2))
        .background(Color.black.opacity(0.6).ignoresSafeArea()) // darker veil over the glossy BG
        .opacity(timeAttackAnimation ? 1 : 0)
        .offset(x: timeAttackAnimation ? 0 : proxy.size.width)
    }
    
    @ViewBuilder func backButton() -> some View {
        BackButton(title: diffculty == .tutorial ? "skip" : "back",
                   action: navBack)
    }
    
    private func navBack() {
        UIApplication.shared.hideKeyboard()
        audio.stop()
        switch diffculty {
        case .tutorial: break
        default:  session.finishRound()
        }
        router.navigateBack()
    }
    
    private func nextLine(i: Int)  {
        colors[i] = vm.calculateColors(with: matrix[i])
        
        let guess = matrix[i].joined()
        
        if guess.lowercased() == vm.word.word.value.lowercased() || i == rows - 1 {
            current = .max
            audio.stop()
            
            let isCorrect = guess.lowercased() == vm.word.word.value.lowercased()
            
            switch diffculty {
            case .tutorial:
                Task(priority: .userInitiated) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard guardVisible() else { return }
                    navBack()
                }
            default:
                let uniqe = uniqe
                let isTimeAttack = vm.word.isTimeAttack
                let rows = rows
                Task.detached(priority: .userInitiated) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await MainActor.run {
                        let sound = isCorrect ? "success" : "fail"
                        audio.playSound(sound: sound,
                                        type: "wav")
                    }
                    let points = isCorrect ? (isTimeAttack ? 40 : 20) : 0
                    let total = rows * points
                    let currentRow = i * points
                    let scoreValue = total - currentRow
                    await score(value: scoreValue)
                    guard let uniqe else { return }
                    await vm.addGuess(diffculty: diffculty, uniqe: uniqe, guess: guess)
                    await vm.score(diffculty: diffculty, uniqe: uniqe, isCorrect: isCorrect)
                    await handleNewWord(uniqe: uniqe)
                }
            }
        } else if i == current && i + 1 > vm.word.word.guesswork.count {
            guard let uniqe else { return }
            current = i + 1
            Task(priority: .userInitiated) {
                await vm.addGuess(diffculty: diffculty, uniqe: uniqe, guess: guess)
            }
        }
    }
    
    private func initMatrixState() {
        matrix = [[String]](repeating: [String](repeating: "",
                                                count: length),
                            count: rows)
        colors = [[CharColor]](repeating: [CharColor](repeating: .noGuess,
                                                      count: length),
                               count: rows)
        cleanCells = false
    }
    
    private func score(value: Int) async {
        scoreAnimation.value = value
        withAnimation(.linear(duration: 1.44)) {
            scoreAnimation.offset = 5
            scoreAnimation.opticity = 0.85
            scoreAnimation.scale = 0.9
        }
        
        try? await Task.sleep(nanoseconds: 1_440_000_000)
        guard guardVisible() else { scoreAnimation = (0, CGFloat(0), CGFloat(0), CGFloat(30)); return }
        if scoreAnimation.opticity == 0.85 {
            withAnimation(.linear(duration: 0.2)) {
                scoreAnimation.opticity = 0
                scoreAnimation.scale = 0
            }
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard guardVisible() else { scoreAnimation = (0, CGFloat(0), CGFloat(0), CGFloat(30)); return }
        let score = vm.score
        if value > 1 {
            let nanoseconds = 80000000 / value
            for i in 1...value {
                try? await Task.sleep(for: .nanoseconds(nanoseconds))
                withAnimation(.easeInOut) {
                    vm.score = score + i
                }
            }
        } else { vm.score = score + value }
        
        scoreAnimation.value = 0
        scoreAnimation.offset = 30
    }
}

struct ProgressBarView: View {
    @EnvironmentObject private var local: LanguageSetting
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    let length: Int
    @State var value: CGFloat
    @State private var trigger = 0
    let total: CGFloat
    var colors: [Color] = [.init(hex: "#599cc9"),
                           .init(hex: "#437da3"),
                           .init(hex: "#2c6185"),
                           .init(hex: "#165178")]
    let done: () -> ()
    
    @State private var waveOffset: CGFloat = 0.0
    @State private var current = 0
    
    private var every: CGFloat = 0.01
    private let timer: Publishers.Autoconnect<Timer.TimerPublisher>
    // cancellation support
    @State private var isActive = true
    
    init(length: Int, value: CGFloat, total: CGFloat, done: @escaping () -> Void) {
        self.length = length
        self.value = value
        self.total = total
        self.done = done
        self.timer = Timer.publish(every: every,
                                   on: .current,
                                   in: .default).autoconnect()
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<length, id: \.self) { i in
                let total = total / CGFloat(length)
                let scope = CGFloat(colors.count) / CGFloat(length)
                let index = Int(scope * CGFloat(i))
                let color = colors[index]
                let nextColor = colors[index < colors.count - 1 ? index + 1: colors.count - 1]
                
                if i == current {
                    progressView(total: total,
                                 value: value.truncatingRemainder(dividingBy: total),
                                 colors: [color, nextColor])
                }
                else if i > current {
                    progressView(total: total,
                                 value: 0,
                                 colors: [color, nextColor])
                }
                else {
                    progressView(total: total,
                                 value: total,
                                 colors: [color, nextColor])
                }
            }
        }
        .onReceive(timer) { _ in
            guard isActive else { return }
            value += every
            current = Int(value / total * CGFloat(length))
            trigger += 1
            
            if value >= total {
                isActive = false
                timer.upstream.connect().cancel()
                done()
            }
        }
        .onDisappear {
            // ensure timer stops if view disappears
            isActive = false
            timer.upstream.connect().cancel()
        }
    }
    
    @ViewBuilder private func progressView(total: CGFloat, value: CGFloat, colors: [Color]) -> some View {
        GeometryReader { geometry in
            let progress = geometry.size.width / total * value
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .systemGray5))
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(gradient: Gradient(colors: colors),
                                       startPoint: language == "he" ? .trailing : .leading,
                                       endPoint: language == "he" ? .leading : .trailing)
                    )
                    .frame(width: progress)
            }
        }
    }
}

extension Color {
    static let tBlue: Color = Color(hex: "#0C8CE9")
    static let tGray: Color = Color(hex: "#ACACAC")
    static let saperatorGrey: Color = Color(hex: "#D9D9D9")
    static let lightText: Color = Color(hex: "#FAFAFA")
    static let darkText: Color = Color(hex: "#131313")
    static let infoText: Color = Color(hex: "#7B7B7B")
    static let progressStart: Color = Color(hex: "#6CC1FF")
    static let progressEnd: Color = Color(hex: "#0094FF")
    static let inputFiled: Color = Color(hex: "#727272")
    static let tYellow: Color = Color(hex: "#FFC100")
    static let gBlack: Color = Color(hex: "#292929")
    static let gWhite: Color = Color(hex: "#FAFAFA")
    static let gBlue: Color = Color(hex: "#D4ECFE")
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:(a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

