//
//  AIGameView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 04/08/2025.
//

import SwiftUI
import CoreData
import Combine
import SwiftUITooltip
import QuartzCore

typealias HpAnimationParams =  (value: Int, opacity: CGFloat, scale: CGFloat, offset: CGFloat)

struct AIGameView<VM: WordViewModelForAI>: View {
    @EnvironmentObject private var coreData: PersistenceController
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var screenManager: ScreenManager
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var premium: PremiumManager
    @EnvironmentObject private var adProvider: AdProvider
    
    fileprivate enum Turn: Int { case player = 0, ai = 1 }
    private enum GameState { case inProgress, lose, win }
    
    private let InterstitialAdInterval: Int = 7
    
    private let rows: Int = 5
    private var length: Int { DifficultyType.ai.getLength() }
    
    private var email: String? { loginHandeler.model?.email }
    private var gender: String? { loginHandeler.model?.gender }
    private var interstitialAdManager: InterstitialAdsManager? { adProvider.interstitialAdsManager(id: "GameInterstitial") }
    
    private let fullHP :Int = 100
    private let hitPoints = 10
    private let noGuessHitPoints = 40
    
    @State private var vm = VM()
    @State private var keyboard = KeyboardHeightHelper()
    @State private var endFetchAnimation = false
    @State private var didStart = false
    
    @State private var aiHpAnimation: HpAnimationParams = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    @State private var playerHpAnimation: HpAnimationParams = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    
    @State private var disabled: Bool = false
    @State private var showGameEndPopup: Bool
    @State private var showExitPopup: Bool
    @State private var showCelebrate: Bool
    @State private var showMourn: Bool
    @State private var showError: Bool
    @State private var wordNumber = 0
    
    // player params
    @State private var current: Int = 0
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var playerHP: Int
    
    // ai params
    @State private var aiMatrix: [[String]]
    @State private var aiColors: [[CharColor]]
    @State private var aiHP: Int
    @State private var ai: AIViewModel?
    @State private var showPhrase: Bool = false
    @State private var showAiIntro: Bool
    @State private var aiDifficulty: AIDifficulty {
        didSet {
            ai?.hidePhrase()
            UserDefaults.standard.set(aiDifficulty.name, forKey: "aiDifficulty")
            UserDefaults.standard.set(playerHP, forKey: "playerHP")
            Task(priority: .utility) { await SharedStore.writeAIStatsAsync(.init(name: aiDifficulty.name, imageName:  aiDifficulty.image)) }
        }
    }
    
    @State private var cleanCells = false
    @State private var aiIntroDone = false
    
    @State private var gameState: GameState {
        didSet {
            ai?.hidePhrase()
            switch gameState {
            case .inProgress: break
            case .lose: showMourn = true
            case .win: showCelebrate = true
            }
        }
    }
    
    // MARK: - Turn FX
    fileprivate struct TurnFX { var show = false; var next: Turn = .player }
    @State private var turnFX = TurnFX()
    
    @State private var turn: Turn {
        didSet {
            switch turn {
            case .player: screenManager.keepScreenOn = false
            case .ai: screenManager.keepScreenOn = true
            }
        }
    }
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    private var allBestGuesses: [BestGuess] { return vm.perIndexCandidatesSparse(matrix: matrix,
                                                                                 colors: colors,
                                                                                 aiMatrix: aiMatrix,
                                                                                 aiColors: aiColors) }
    
    private var firstGuess: (String) -> GuessHistory? {
        { s in
            guard s.count < length else { return nil }
            let pattern = vm.calculateColors(with: s.map { String($0) })
                .map { $0.getColor() }
                .joined()
            return (s, pattern)
        }
    }
    
    private func animatedTurnSwitch(to next: Turn) {
        // disable input while animating
        disabled = (next == .ai)
        
        // present overlay sweep & badge
        turnFX.next = next
        withAnimation(.easeInOut(duration: 0.22)) { turnFX.show = true }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        
        Task(priority: .userInitiated) {
            // flip board shortly after sweep begins
            try? await Task.sleep(nanoseconds: 260_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) {
                    turn = next
                }
            }
            // let badge linger then fade overlay
            try? await Task.sleep(nanoseconds: 420_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { turnFX.show = false }
            }
        }
    }
    
    private func handleWordChange() {
        initMatrixState()
        wordNumber += 1
        guard interstitialAdManager == nil || wordNumber % InterstitialAdInterval != 0 else {
            disabled = true
            interstitialAdManager?.loadInterstitialAd()
            return
        }
        initalConfigirationForWord()
    }
    
    private func handleError() {
        guard !vm.fatalError else { showError = true; return }
        guard vm.word == .empty && vm.numberOfErrors > 0 else { return }
        guard let email else { showError = true; return }
        Task.detached(priority: .userInitiated) { await vm.word(email: email) }
    }
    
    private func handleStartup(email: String) async {
        await vm.word(email: email)
        await MainActor.run { didStart = vm.word != .empty }
    }
    
    private func backButtonTap() {
        if endFetchAnimation { showExitPopup = true }
        else { closeView() }
    }
    
    private func gameFinish() {
        switch gameState {
        case .lose: clearSaved()
        default: break
        }
        closeView()
    }
    
    private func clearSaved() {
        UserDefaults.standard.set(nil, forKey: "playerHP")
        UserDefaults.standard.set(nil, forKey: "aiDifficulty")
        Task(priority: .utility) { await SharedStore.writeAIStatsAsync(.init(name: AIDifficulty.easy.name, imageName: AIDifficulty.easy.image)) }
    }
    
    private func closeView() {
        screenManager.keepScreenOn = false
        ai?.hidePhrase()
        ai?.deassign()
        audio.stop()
        
        if vm.fatalError || ai == nil || !ai!.isReadyToGuess { router.navigateBack() }
        else {
            Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await MainActor.run { router.navigateBack() }
            }
        }
    }
    
    private func closeViewAfterErorr() {
        keyboard.show = true
        closeView()
    }
    
    private func chackWord(index i: Int, matrix: [[String]]) -> Bool {
        let guess = matrix[i].joined()
        
        if guess.lowercased() == vm.wordValue.lowercased() || i == rows - 1 {
            disabled = true
            audio.stop()
            
            let correct = guess.lowercased() == vm.wordValue.lowercased()
            
            if correct {
                Task(priority: .userInitiated) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard let email else { return }
                    await vm.word(email: email)
                }
                return true
            }
            return false
        } else {
            guard let value = Turn(rawValue: 1 - turn.rawValue) else { return false }
            disabled = value == .ai
            Task(priority: .high) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { animatedTurnSwitch(to: value) }
            }
            return false
        }
    }
    
    private func makeHitOnPlayer(hitPoints: Int) { makeHit(hp: $playerHP, hpParams: $playerHpAnimation, hitPoints: hitPoints) }
    private func makeHitOnAI(hitPoints: Int) { makeHit(hp: $aiHP, hpParams: $aiHpAnimation, hitPoints: hitPoints) }
    private func makeHit(hp: Binding<Int>, hpParams: Binding<HpAnimationParams>, hitPoints: Int) {
        current = .max
        ai?.hidePhrase()
        
        hpParams.wrappedValue.value = hitPoints
        
        withAnimation(.linear(duration: 1.4)) {
            hpParams.wrappedValue.offset = -30
            hpParams.wrappedValue.opacity = 1
            hpParams.wrappedValue.scale = 1.6
        }
        
        Task(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 1_440_000_000)
            guard hpParams.wrappedValue.opacity == 1 else { return }
            await MainActor.run {
                withAnimation(.linear(duration: 0.4)) {
                    hpParams.wrappedValue.opacity = 0
                    hpParams.wrappedValue.scale = 0
                    let newHP = hp.wrappedValue - hitPoints
                    hp.wrappedValue = max(0, newHP)
                }
            }
            
            try? await Task.sleep(nanoseconds: 400_000_000)
            hpParams.wrappedValue.value = 0
            hpParams.wrappedValue.offset = 30
        }
    }
    
    private func initMatrixState() {
        matrix = [[String]](repeating: [String](repeating: "", count: length),
                            count: rows)
        
        colors = [[CharColor]](repeating: [CharColor](repeating: .noGuess, count: length),
                               count: rows)
        
        aiMatrix = [[String]](repeating: [String](repeating: "", count: length),
                              count: rows)
        
        aiColors = [[CharColor]](repeating: [CharColor](repeating: .noGuess, count: length),
                                 count: rows)
        
        ai?.hidePhrase()
        
        cleanCells = false
        
        ai?.manageMemory(with: []) {
            switch aiDifficulty {
            case .boss: return vm.wordValue
            default: return nil
            }
        }
        
        guard turn != .player else { return }
        animatedTurnSwitch(to: .player)
    }
    
    init() {
        AIPackManager().migrateIfNeeded()
        
        self.matrix = [[String]](repeating: [String](repeating: "",
                                                     count: DifficultyType.ai.getLength()),
                                 count: rows)
        
        self.colors = [[CharColor]](repeating: [CharColor](repeating: .noGuess,
                                                           count: DifficultyType.ai.getLength()),
                                    count: rows)
        
        self.aiMatrix = [[String]](repeating: [String](repeating: "",
                                                       count: DifficultyType.ai.getLength()),
                                   count: rows)
        
        self.aiColors = [[CharColor]](repeating: [CharColor](repeating: .noGuess,
                                                             count: DifficultyType.ai.getLength()),
                                      count: rows)
        
        self.showGameEndPopup = false
        self.showExitPopup = false
        self.showAiIntro = false
        self.aiIntroDone = false
        self.showCelebrate = false
        self.showMourn = false
        self.showError = false
        self.current = 0
        self.aiHP = fullHP
        
        let playerHP = UserDefaults.standard.integer(forKey: "playerHP")
        self.playerHP = playerHP > 0 ? playerHP : fullHP
        
        self.turn = .player
        self.gameState = .inProgress
        
        let difficulty = UserDefaults.standard.string(forKey: "aiDifficulty")
        switch difficulty ?? AIDifficulty.easy.name {
        case AIDifficulty.easy.name:   aiDifficulty = .easy
        case AIDifficulty.medium.name: aiDifficulty = .medium
        case AIDifficulty.hard.name:   aiDifficulty = .hard
        case AIDifficulty.boss.name:   aiDifficulty = .boss
        default: fatalError()
        }
    }
    
    private func aiIntroToggle() {
        Task.detached(priority: .userInitiated) {
            await MainActor.run { withAnimation(.easeInOut(duration: 2.5)) { showAiIntro = true } }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { withAnimation(.easeInOut(duration: 1.5)) { showAiIntro = false } }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { aiIntroDone = true }
        }
    }
    
    private func handleAi() {
        guard playerHP > 0 else { return }
        guard aiHP == 0 else { return }
        switch aiDifficulty {
        case .easy:   withAnimation { aiDifficulty = .medium }
        case .medium: withAnimation { aiDifficulty = .hard }
        case .hard:   withAnimation { aiDifficulty = .boss }
        case .boss:   gameState = .win
        }
        guard gameState == .inProgress else { return  }
        aiHP = fullHP
    }
    
    private func handleWin() {
        guard gameState == .win && !showCelebrate else { return }
        showGameEndPopup = true
    }
    
    private func handleLose() {
        guard gameState == .lose && !showMourn else { return }
        showGameEndPopup = true
    }
    
    private func handlePlayer() {
        guard playerHP == 0 else { return }
        gameState = .lose
    }
    
    private func handleInterstitial() {
        guard interstitialAdManager?.interstitialAdLoaded ?? false else { initalConfigirationForWord(); return }
        interstitialAdManager?.displayInterstitialAd { initalConfigirationForWord() }
    }
    
    private func initializeAI() {
        guard vm.aiDownloaded && ai == nil else { return }
        guard let lang = language, let language = Language(rawValue: lang) else { return }
        ai               = .init(language: language)
        let aiDifficulty = aiDifficulty
        let playerHP     = playerHP
        UserDefaults.standard.set(aiDifficulty.name, forKey: "aiDifficulty")
        UserDefaults.standard.set(playerHP, forKey: "playerHP")
        Task.detached(priority: .utility) { await SharedStore.writeAIStatsAsync(.init(name: aiDifficulty.name, imageName: aiDifficulty.image)) }
    }
    
    private func handlePhrase() { showPhrase = ai?.showPhraseValue ?? false }
    
    private func handleAiIntroToggle<T: Equatable>(oldValue: T, newValue: T) {
        guard oldValue != newValue && (!(type(of: newValue) is Bool.Type) || (newValue as! Bool)) else { return }
        aiIntroToggle()
    }
    
    private func handleEndFetchAnimation<T: Equatable>(oldValue: T, newValue: T) {
        guard let ai else { return }
        handleAiIntroToggle(oldValue: oldValue, newValue: newValue)
        
        Task.detached(priority: .high) {
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            await MainActor.run { ai.startShowingPhrase() }
        }
    }
    
    private func hanldePlayerTurnAfterAiChange() {
        guard aiIntroDone else { return }
        animatedTurnSwitch(to: .player)
    }
    
    private func getAiWord() {
        guard let ai else { return }
        let row = current
        let aiDifficulty = aiDifficulty
        var arr = [String](repeating: "", count: length)
        
        Task.detached(priority: .high) {
            let aiWord = await ai.getFeedback(for: aiDifficulty).capitalizedFirst.toArray()
            try? await Task.sleep(nanoseconds: 500_000_000)
            for i in 0..<aiWord.count {
                arr[i] = aiWord[i].returnChar(isFinal: i == aiWord.count - 1)
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    if aiMatrix.indices.contains(row) { aiMatrix[row] = arr }
                }
            }
        }
    }
    
    private func saveToHistory(for type: Turn) {
        switch turn {
        case .player:
            let idx = current
            guard matrix.indices.contains(idx),
                  colors.indices.contains(idx),
                  aiMatrix.indices.contains(idx),
                  aiMatrix[idx].allSatisfy(\.isEmpty) else { return }
            let guess   = matrix[idx].joined()
            let pattern = colors[idx].map { $0.getColor() }.joined()
            ai?.saveToHistory(guess: (guess, pattern))
        case .ai:
            let idx = current - 1
            guard idx >= 0,
                  aiMatrix.indices.contains(idx),
                  aiColors.indices.contains(idx) else { return }
            let guess   = aiMatrix[idx].joined()
            let pattern = aiColors[idx].map { $0.getColor() }.joined()
            ai?.saveToHistory(guess: (guess, pattern))
        }
    }
    
    private func calculatePlayerTurn(i: Int) {
        guard i == current else { return }
        colors[i] = vm.calculateColors(with: matrix[i])
        saveToHistory(for: .player)
        if chackWord(index: i, matrix: matrix) {
            audio.playSound(sound: "success", type: "wav")
            makeHitOnAI(hitPoints: rows * hitPoints - current * hitPoints)
        } else {
            if current == rows - 1 {
                Task(priority: .high) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await MainActor.run { animatedTurnSwitch(to: .ai) }
                }
            }
            getAiWord()
        }
    }
    
    private func calculateAITurn(i: Int) {
        guard i == current else { return }
        aiColors[i] = vm.calculateColors(with: aiMatrix[i])
        saveToHistory(for: .ai)
        if chackWord(index: i, matrix: aiMatrix) {
            audio.playSound(sound: "fail", type: "wav")
            makeHitOnPlayer(hitPoints: rows * hitPoints - current * hitPoints)
        }
        else if current < rows - 1 { current = i + 1 }
        else if current == rows - 1 {
            audio.playSound(sound: "fail", type: "wav")
            makeHitOnPlayer(hitPoints: noGuessHitPoints)
            makeHitOnAI(hitPoints: noGuessHitPoints)
            Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let email else { return }
                await vm.word(email: email)
            }
        }
    }
    
    private func initalConfigirationForWord() {
        audio.playSound(sound: "backround",
                        type: "mp3",
                        loop: true)
        endFetchAnimation = true
        disabled = false
        current = 0
        Task(priority: .high) { await ai?.addDetachedFirstGuess(with: firstGuess) }
    }
    
    var body: some View {
        bodyContant()
            .onAppear { initializeAI() }
            .onChange(of: vm.aiDownloaded, initializeAI)
            .onChange(of: ai?.showPhraseValue, handlePhrase)
    }
    
    @ViewBuilder private func bodyContant() -> some View {
        if let ai, ai.isReadyToGuess { contant() }
        else if vm.aiDownloaded { AIPackLoadingView(onCancel: closeView) }
        else { AIPackDownloadView(downloaded: $vm.aiDownloaded, onCancel: closeView) }
    }
    
    @ViewBuilder private func contant() -> some View {
        GeometryReader { _ in
            background()
            ZStack(alignment: .top) {
                topBar().padding(.top, 4)
                game().padding(.top, 10)
                overlayViews()
                
                // Turn-change overlay on top (NOW SYMMETRIC)
                TurnChangeOverlay(isPresented: $turnFX.show,
                                  isAI: turnFX.next == .ai,
                                  language: language)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: aiDifficulty, handleAiIntroToggle)
        .onChange(of: endFetchAnimation, handleEndFetchAnimation)
        .onChange(of: aiIntroDone, hanldePlayerTurnAfterAiChange)
        .onChange(of: interstitialAdManager?.interstitialAdLoaded, handleInterstitial)
        .onChange(of: playerHP, handlePlayer)
        .onChange(of: aiHP, handleAi)
        .onChange(of: showCelebrate, handleWin)
        .onChange(of: showMourn, handleLose)
        .celebrate($showCelebrate)
        .mourn($showMourn)
        .customAlert("YOU vs AI",
                     type: gameState == .win ? .success : .fail,
                     isPresented: $showGameEndPopup,
                     actionText: "OK",
                     action: gameFinish,
                     message: { Text("You \(gameState == .win ? "win".localized : "lose".localized)") })
        .customAlert("Exit",
                     type: .info,
                     isPresented: $showExitPopup,
                     actionText: "OK",
                     cancelButtonText: "Cancel",
                     action: closeView,
                     message: { Text("By exiting you will lose all progress") })
        .customAlert("Network error",
                     type: .fail,
                     isPresented: $showError,
                     actionText: "OK",
                     action: closeViewAfterErorr,
                     message: { Text("something went wrong") })
    }
    
    @ViewBuilder private func topBar() -> some View {
        HStack {
            backButton()
            Spacer()
            adProvider.adView(id: "GameBanner")
            Spacer()
        }
    }
    
    @ViewBuilder private func background() -> some View {
        GameViewBackguard()
            .ignoresSafeArea()
    }
    
    @ViewBuilder private func aiIntro() -> some View {
        ZStack {
            Color.white
                .circleReveal(trigger: $showAiIntro)
                .ignoresSafeArea()
            
            VStack {
                Text(aiDifficulty.name.localized)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(aiDifficulty.color)
                
                Image(aiDifficulty.image)
                    .resizable()
                    .scaledToFill()
                    .shadow(radius: 4)
                    .frame(width: 240,
                           height: 240)
            }
            .opacity(showAiIntro ? 1 : 0)
        }
        .frame(maxWidth: .infinity,
               maxHeight: .infinity)
    }
    
    @ViewBuilder private func topViews() -> some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .top) {
                ZStack(alignment: .trailing) {
                    HStack {
                        Spacer()
                        VStack {
                            ZStack {
                                Image("player_\(gender ?? "male")")
                                    .resizable()
                                    .scaledToFill()
                                    .shadow(radius: 4)
                                    .frame(width: 50, height: 50)
                                    .opacity(turn == .player ? 1 : 0.4)
                            }
                            
                            ZStack {
                                HPBar(value: Double(playerHP), maxValue: Double(fullHP))
                                    .frame(width: 100)
                                
                                Text("- \(playerHpAnimation.value)")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .foregroundStyle(.red)
                                    .opacity(playerHpAnimation.opacity)
                                    .scaleEffect(.init(width: playerHpAnimation.scale,
                                                       height: playerHpAnimation.scale))
                                    .offset(x: playerHpAnimation.scale > 0 ? (language == "he" ? 12 : -12) : 0,
                                            y: playerHpAnimation.offset)
                                    .blur(radius: 0.5)
                                    .fixedSize()
                            }
                            .padding(.bottom, 5)
                        }
                        
                        Spacer()
                        
                        VStack {
                            ZStack {
                                Image(aiDifficulty.image)
                                    .resizable()
                                    .scaledToFill()
                                    .shadow(radius: 4)
                                    .frame(width: 50, height: 50)
                                    .opacity(turn == .ai ? 1 : 0.4)
                                    .tooltip(ai!.phrase,
                                             language: language == "he" ? .he : .en,
                                             trigger: .manual,
                                             isPresented: $showPhrase)
                            }
                            
                            ZStack {
                                HPBar(value: Double(aiHP), maxValue: Double(fullHP))
                                    .frame(width: 100)
                                
                                Text("- \(aiHpAnimation.value)")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .foregroundStyle(.red)
                                    .opacity(aiHpAnimation.opacity)
                                    .scaleEffect(.init(width: aiHpAnimation.scale,
                                                       height: aiHpAnimation.scale))
                                    .offset(x: aiHpAnimation.scale > 0 ? (language == "he" ? 12 : -12) : 0,
                                            y: aiHpAnimation.offset)
                                    .blur(radius: 0.5)
                                    .fixedSize()
                            }
                            .padding(.bottom, 5)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.vertical)
            }
            .shadow(radius: 4)
        }
    }
    
    @ViewBuilder private func gameBody() -> some View {
        if !vm.fatalError && didStart {
            VStack(spacing: 8) {
                topViews()
                    .padding(.top, -10)
                    .padding(.bottom, -20)
                
                ForEach(0..<rows, id: \.self) { i in
                    ZStack {
                        switch turn {
                        case .player:
                            let hasPrevAIGuess = i > 0 && current == i && aiMatrix[current - 1].contains { !$0.isEmpty }
                            let placeHolderData = hasPrevAIGuess ? allBestGuesses : nil
                            let gainFocus = Binding(get: { !showAiIntro && aiIntroDone && current == i }, set: { _ in })
                            WordView(
                                cleanCells: $cleanCells,
                                current: $current,
                                length: length,
                                placeHolderData: placeHolderData,
                                word: $matrix[i],
                                gainFocus: gainFocus,
                                colors: $colors[i],
                                done: { calculatePlayerTurn(i: i) }
                            )
                            .allowsHitTesting(!disabled && current == i)
                            .disabled(disabled || current != i)
                            .shadow(radius: 4)
                            // IMPROVED FLIP
                            .cardFlip(degrees: turn == .ai ? 180 : 0)
                            
                        case .ai:
                            let isAIRowActive = current == i && matrix[current].contains { !$0.isEmpty }
                            WordView(
                                cleanCells: $cleanCells,
                                isAI: true,
                                current: $current,
                                length: length,
                                isCurrentRow: isAIRowActive,
                                word: $aiMatrix[i],
                                gainFocus: .constant(false),
                                colors: $aiColors[i],
                                done: { calculateAITurn(i: i) }
                            )
                            .allowsHitTesting(false)
                            .disabled(true)
                            .shadow(radius: 4)
                            // IMPROVED FLIP
                            .cardFlip(degrees: 180)
                        }
                    }
                    // Row container flip (board-level)
                    .boardFlip(isAI: turn == .ai)
                }
                
                if endFetchAnimation {
                    AppTitle(size: 50)
                        .padding(.top, UIDevice.isPad ? 130 : 95)
                        .padding(.bottom, UIDevice.isPad ? 190 : 145)
                        .shadow(radius: 4)
                } else {
                    ZStack{}
                        .frame(height: UIDevice.isPad ? 81 : 86)
                        .padding(.top, UIDevice.isPad ? 130 : 95)
                        .padding(.bottom, UIDevice.isPad ? 190 : 140)
                        .shadow(radius: 4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, -10)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)
        }
    }
    
    @ViewBuilder private func game() -> some View {
        if let email {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) { gameBody() }
                    .ignoresSafeArea(.keyboard)
                    .onAppear { Task.detached(priority: .userInitiated, operation: { await handleStartup(email: email) } ) }
                    .onChange(of: vm.numberOfErrors, handleError)
                    .onChange(of: vm.word, handleWordChange)
                    .ignoresSafeArea(.keyboard)
            }
            .padding(.top, 44)
        }
    }
    
    @ViewBuilder private func overlayViews() -> some View {
        if !vm.fatalError && !endFetchAnimation && !keyboard.show { FetchingView(word: vm.wordValue) }
        else { aiIntro() }
    }
    
    @ViewBuilder func backButton() -> some View {
        HStack {
            BackButton(action: backButtonTap)
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).capitalized + dropFirst() }
    
    func numberOfOccurrences(of needle: String,
                             overlapping: Bool = false,
                             options: String.CompareOptions = []) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange: Range<String.Index>? = startIndex..<endIndex
        
        while let found = range(of: needle, options: options, range: searchRange) {
            count += 1
            let nextStart = overlapping
            ? index(after: found.lowerBound)
            : found.upperBound
            searchRange = nextStart..<endIndex
        }
        return count;
    }
}

// MARK: - Turn Change Overlay (sweep + badge, symmetric)
fileprivate struct TurnChangeOverlay: View {
    @Binding var isPresented: Bool
    var isAI: Bool
    var language: String?
    @Environment(\.colorScheme) private var scheme
    
    private var direction: SweepStripe.Direction { isAI ? .rightToLeft : .leftToRight }
    
    var body: some View {
        ZStack {
            if isPresented {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(scheme == .dark ? 0.25 : 0.22)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                // Dual-layer sweep with soft edge mask, mirrored by role
                SweepStripe(accent: accent, direction: direction)
                    .allowsHitTesting(false)
                
                VStack {
                    Text(label)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .kerning(language == "he" ? 0.0 : 0.3)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThickMaterial, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule().stroke(accent.opacity(0.55), lineWidth: 1)
                                .shadow(color: accent.opacity(0.35), radius: 6)
                        )
                        .shadow(radius: 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.32), value: isPresented)
    }
    
    private var label: String {
        isAI ? "AI’s Turn".localized : "Your Turn".localized
    }
    private var accent: Color { isAI ? .pink : .cyan }
}

// MARK: - Diagonal moving light stripe (mirrored + layered)
fileprivate struct SweepStripe: View {
    enum Direction { case leftToRight, rightToLeft }
    var accent: Color
    var direction: Direction = .leftToRight
    @State private var run = false
    
    var body: some View {
        GeometryReader { geo in
            let L = max(geo.size.width, geo.size.height) * 1.8
            let startX = (direction == .leftToRight) ? -L :  L
            let endX   = (direction == .leftToRight) ?  L : -L
            let angle: Double = (direction == .leftToRight) ? -18 : 18
            
            ZStack {
                // Main band
                LinearGradient(
                    colors: [accent.opacity(0.00), accent.opacity(0.36), accent.opacity(0.00)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: L * 0.58, height: L)
                .mask(
                    LinearGradient(colors: [.clear, .white, .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                .blur(radius: 10)
                .offset(x: run ? endX : startX)
                .animation(.easeInOut(duration: 0.70), value: run)
                
                // Echo band (slightly thinner, delayed for depth)
                LinearGradient(
                    colors: [accent.opacity(0.00), accent.opacity(0.24), accent.opacity(0.00)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: L * 0.42, height: L)
                .mask(
                    LinearGradient(colors: [.clear, .white, .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                .blur(radius: 14)
                .offset(x: run ? endX : startX)
                .animation(.easeInOut(duration: 0.86).delay(0.06), value: run)
                
                // Crisp center line for a premium feel
                Rectangle()
                    .fill(accent.opacity(0.45))
                    .frame(width: 2.0, height: L)
                    .blur(radius: 0.6)
                    .offset(x: run ? endX : startX)
                    .animation(.easeInOut(duration: 0.72), value: run)
            }
            .rotationEffect(.degrees(angle))
            .onAppear { run = true }
        }
        .ignoresSafeArea()
    }
}

// MARK: - High-quality 3D Flip (perspective + lift + mid-flip blur)
fileprivate struct Flip3D: AnimatableModifier {
    var degrees: Double
    var axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (0, 1, 0)
    var perspective: CGFloat = -1/800
    var lift: CGFloat = 16
    var blurMax: CGFloat = 1.1
    var scaleDelta: CGFloat = 0.03
    var specularStrength: Double = 0.18
    
    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }
    
    func body(content: Content) -> some View {
        let rad   = CGFloat(degrees) * .pi / 180
        let s     = abs(sin(rad))                    // 0 → 1 (peaks at 90°)
        let liftY = -lift * s
        let scale = 1 - scaleDelta * s
        let blur  = blurMax * s
        let shade = min(0.22, 0.22 * Double(s))
        
        return content
            .overlay(specularOverlay(intensity: s * s))   // subtle, not a halo
            .scaleEffect(scale)
            .offset(y: liftY)
            .shadow(color: .black.opacity(shade), radius: 14 * s, y: 10 * s)
            .blur(radius: blur)
            .modifier(Projection3D(angle: rad, axis: axis, m34: perspective))
    }
    
    @ViewBuilder
    private func specularOverlay(intensity: CGFloat) -> some View {
        if intensity > 0.05 {
            LinearGradient(
                colors: [.clear, Color.white.opacity(specularStrength * Double(intensity)), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .blendMode(.plusLighter)
            .rotationEffect(.degrees(-16))
            .opacity(Double(intensity))
        } else {
            EmptyView()
        }
    }
    
    private struct Projection3D: ViewModifier {
        let angle: CGFloat
        let axis: (x: CGFloat, y: CGFloat, z: CGFloat)
        let m34: CGFloat
        func body(content: Content) -> some View {
            var t = CATransform3DIdentity
            t.m34 = m34
            t = CATransform3DRotate(t, angle, axis.x, axis.y, axis.z)
            return content.projectionEffect(ProjectionTransform(t))
        }
    }
}

// Convenience wrappers for board vs. card
fileprivate extension View {
    func boardFlip(isAI: Bool) -> some View {
        self.modifier(
            Flip3D(
                degrees: isAI ? 180 : 0,
                axis: (0,1,0),
                perspective: -1/850,
                lift: 18,
                blurMax: 1.3,
                scaleDelta: 0.035,
                specularStrength: 0.16
            )
        )
    }
    func cardFlip(degrees: Double) -> some View {
        self.modifier(
            Flip3D(
                degrees: degrees,
                axis: (0,1,0),
                perspective: -1/900,
                lift: 10,
                blurMax: 0.9,
                scaleDelta: 0.02,
                specularStrength: 0.14
            )
        )
    }
}
