//
//  AIGameView.swift
//  WordZap
//
//  Created by Barak Ben Hur on 04/08/2025.
//

import SwiftUI
import CoreData
import Combine
import SwiftUITooltip
import QuartzCore

typealias HpAnimationParams =  (value: Int, opacity: CGFloat, scale: CGFloat, offset: CGFloat)

struct AIGameView<VM: AIWordViewModel>: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var coreData: PersistenceController
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var screenManager: ScreenManager
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var premium: PremiumManager
    @EnvironmentObject private var session: GameSessionManager
    
    private enum Turn: Int { case player = 0, ai = 1 }
    private enum HitTarget { case player, ai }
    private enum GameState { case inProgress, lose, win }
    private struct TurnFX { var show = false; var next: Turn = .player }
    
    
    private let rows: Int = 5
    private var length: Int { DifficultyType.ai.getLength() }
    
    private var uniqe: String? { loginHandeler.model?.uniqe }
    
    private let fullHP :Int = 100
    private let hitPoints = 10
    private let noGuessHitPoints = 40
    
    @State private var vm = VM()
    @State private var endFetchAnimation: Bool
    @State private var didStart: Bool
    @State private var gender: String
    
    @State private var turnFX = TurnFX()
    
    @State private var aiHpAnimation: HpAnimationParams = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    @State private var playerHpAnimation: HpAnimationParams = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    
    @State private var interstitialAdManager: InterstitialAdsManager?
    @State private var disabled: Bool
    @State private var showGameEndPopup: Bool
    @State private var showExitPopup: Bool
    @State private var showCelebrate: Bool
    @State private var showMourn: Bool
    @State private var showError: Bool
    
    // player params
    @State private var current: Int
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var playerHP: Int
    
    // ai params
    @State private var aiMatrix: [[String]]
    @State private var aiColors: [[CharColor]]
    @State private var aiHP: Int
    @State private var ai: AIViewModel?
    @State private var showPhrase: Bool
    @State private var showAiIntro: Bool
    @State private var aiDifficulty: AIDifficulty {
        didSet {
            ai?.hidePhrase()
            UserDefaults.standard.set(aiDifficulty.name, forKey: "aiDifficulty")
            UserDefaults.standard.set(playerHP, forKey: "playerHP")
            Task(priority: .utility) { await SharedStore.writeAIStatsAsync(.init(name: aiDifficulty.name, imageName:  aiDifficulty.image)) }
        }
    }
    
    @State private var aiDifficultyPanding: AIDifficulty
    @State private var aiDifficultyShow: AIDifficulty
    
    @State private var cleanCells: Bool
    @State private var aiIntroDone: Bool
    
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
    
    // MARK: - Task control
    @State private var isVisible: Bool
    @State private var hitTaskPlayer: Task<Void, Never>?
    @State private var hitTaskAI: Task<Void, Never>?
    @State private var delayedNavTask: Task<Void, Never>?
    @State private var delayedTurnTask: Task<Void, Never>?
    @State private var phraseTask: Task<Void, Never>?
    
    @State private var aiTypeToken = UUID()
    @State private var playerHitToken = UUID()
    @State private var aiHitToken = UUID()
    
    private func cancelAllTasks() {
        hitTaskPlayer?.cancel(); hitTaskPlayer = nil
        hitTaskAI?.cancel(); hitTaskAI = nil
        delayedNavTask?.cancel(); delayedNavTask = nil
        delayedTurnTask?.cancel(); delayedTurnTask = nil
        phraseTask?.cancel(); phraseTask = nil
    }
    
    private func guardVisible() -> Bool { isVisible && !Task.isCancelled }
    
    private func animatedTurnSwitch(to next: Turn) {
        // cancel any pending flip before starting a new one
        delayedTurnTask?.cancel()
        disabled = (next == .ai)
        turnFX.next = next
        withAnimation(.easeInOut(duration: 0.22)) { turnFX.show = true }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        
        delayedTurnTask = Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard guardVisible() else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) {
                    turn = next
                }
            }
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard guardVisible() else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { turnFX.show = false }
            }
        }
    }
    
    private func handleWordChange() {
        cancelAllTasks()
        ai?.hidePhrase()
        initMatrixState()
        guard interstitialAdManager == nil || !interstitialAdManager!.shouldShowInterstitial(for: vm.wordCount) else {
            disabled = true
            interstitialAdManager?.loadInterstitialAd()
            return
        }
        initalConfigirationForWord()
    }
    
    private func handleError() {
        guard !vm.fatalError else { showError = true; return }
        guard vm.word == .empty && vm.numberOfErrors > 0 else { return }
        guard let uniqe else { showError = true; return }
        Task.detached(priority: .high) {
            await vm.word(uniqe: uniqe, newWord: didStart)
            await MainActor.run {
                guard !didStart else { return }
                didStart = vm.word != .empty
            }
        }
    }
    
    private func onAppear(uniqe: String) {
        guard !didStart && (interstitialAdManager == nil || !interstitialAdManager!.initialInterstitialAdLoaded) else { return }
        hitTaskPlayer?.cancel()
        hitTaskAI?.cancel()
        phraseTask?.cancel()
        aiTypeToken = UUID()
        gender = loginHandeler.model?.gender ?? "male"
        session.startNewRound(id: .ai)
        interstitialAdManager = AdProvider.interstitialAdsManager(id: "GameInterstitial")
        if let interstitialAdManager {
            interstitialAdManager.displayInitialInterstitialAd {
                guard guardVisible() else { return }
                Task.detached(priority: .userInitiated) {
                    await handleStartup(uniqe: uniqe)
                }
            }
        } else {
            Task.detached(priority: .userInitiated) {
                await handleStartup(uniqe: uniqe)
            }
        }
    }
    
    private func handleStartup(uniqe: String) async {
        await vm.word(uniqe: uniqe, newWord: false)
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
        Task.detached(priority: .utility) {
            await SharedStore.writeAIStatsAsync(.init(name: AIDifficulty.easy.name, imageName: AIDifficulty.easy.image))
        }
    }
    
    private func closeView() {
        UIApplication.shared.hideKeyboard()
        cancelAllTasks()
        screenManager.keepScreenOn = false
        ai?.release()
        audio.stop()
        session.finishRound()
        aiTypeToken = UUID()
        
        if vm.fatalError || ai == nil || !ai!.isReadyToGuess {
            router.navigateBack()
        } else {
            delayedNavTask?.cancel()
            delayedNavTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard guardVisible() else { return }
                await MainActor.run { router.navigateBack() }
            }
        }
    }
    
    private func closeViewAfterErorr() {
        closeView()
    }
    
    private func chackWord(index i: Int, matrix: [[String]]) -> Bool {
        let guess = matrix[i].joined()
        
        if guess.lowercased() == vm.wordValue.lowercased() || i == rows - 1 {
            disabled = true
            audio.stop()
            
            let correct = guess.lowercased() == vm.wordValue.lowercased()
            return correct
        } else {
            guard let value = Turn(rawValue: 1 - turn.rawValue) else { return false }
            disabled = value == .ai
            delayedTurnTask?.cancel()
            delayedTurnTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard guardVisible() else { return }
                await MainActor.run { animatedTurnSwitch(to: value) }
            }
            return false
        }
    }
    
    private func setPandingAiDifficultyIfNeeded(hitPoints: Int) {
        if aiHP - hitPoints <= 0 {
            switch aiDifficulty {
            case .easy:   aiDifficultyPanding = .medium
            case .medium: aiDifficultyPanding = .hard
            case .hard:   aiDifficultyPanding = .boss
            case .boss:   break
            }
        }
    }
    
    private func makeHitOnAI(hitPoints: Int) {
        setPandingAiDifficultyIfNeeded(hitPoints: hitPoints)
        makeHit(hp: $aiHP, hpParams: $aiHpAnimation, token: &aiHitToken, hitPoints: hitPoints, assignTo: .ai)
    }
    
    private func makeHitOnPlayer(hitPoints: Int) { makeHit(hp: $playerHP, hpParams: $playerHpAnimation, token: &playerHitToken, hitPoints: hitPoints, assignTo: .player) }
    
    private func makeHit(hp: Binding<Int>, hpParams: Binding<HpAnimationParams>, token: inout UUID, hitPoints: Int, assignTo: HitTarget) {
        current = .max
        ai?.hidePhrase()
        
        token = UUID() // new generation
        let myToken = token
        let currentToken = myToken // capture immutable snapshot for the Task
        
        let taskRef = (assignTo == .player) ? \AIGameView.hitTaskPlayer : \AIGameView.hitTaskAI
        self[keyPath: taskRef]?.cancel()
        self[keyPath: taskRef] = Task {
            await MainActor.run {
                hpParams.wrappedValue.value = hitPoints
                withAnimation(.linear(duration: 1.4)) {
                    hpParams.wrappedValue.offset = -30
                    hpParams.wrappedValue.opacity = 1
                    hpParams.wrappedValue.scale = 1.6
                }
            }
            try? await Task.sleep(nanoseconds: 1_440_000_000)
            guard guardVisible(), myToken == currentToken else { return }
            await MainActor.run {
                withAnimation(.linear(duration: 0.4)) {
                    hpParams.wrappedValue.opacity = 0
                    hpParams.wrappedValue.scale = 0
                    let newHP = hp.wrappedValue - hitPoints
                    hp.wrappedValue = max(0, newHP)
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard guardVisible(), myToken == currentToken else { return }
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
        self.cleanCells = false
        self.showPhrase = false
        self.endFetchAnimation = false
        self.didStart = false
        self.disabled = false
        self.isVisible = false
        self.gender = "male"
        self.current = 0
        self.aiHP = fullHP
        
        let playerHP = UserDefaults.standard.integer(forKey: "playerHP")
        self.playerHP = playerHP > 0 ? playerHP : fullHP
        
        self.turn = .player
        self.gameState = .inProgress
        
        let difficulty = UserDefaults.standard.string(forKey: "aiDifficulty")
        var aiDifficultyVal: AIDifficulty!
        switch difficulty ?? AIDifficulty.easy.name {
        case AIDifficulty.easy.name:   aiDifficultyVal = .easy
        case AIDifficulty.medium.name: aiDifficultyVal = .medium
        case AIDifficulty.hard.name:   aiDifficultyVal = .hard
        case AIDifficulty.boss.name:   aiDifficultyVal = .boss
        default:                       fatalError()
        }
        
        self.aiDifficulty = aiDifficultyVal
        self.aiDifficultyShow = aiDifficultyVal
        self.aiDifficultyPanding = aiDifficultyVal
    }
    
    private func aiIntroToggle() {
        Task {
            await MainActor.run { aiIntroDone = false }
            await MainActor.run { withAnimation(.easeInOut(duration: 0.9)) { showAiIntro = true } }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard guardVisible() else { return }
            await MainActor.run { withAnimation(.easeInOut(duration: 0.6)) { showAiIntro = false } }
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard guardVisible() else { return }
            let currentShow = aiDifficultyShow
            await MainActor.run {
                aiDifficultyShow = aiDifficulty
                aiHP = fullHP
                aiIntroDone = true
            }
            guard let uniqe else { return }
            if currentShow != aiDifficulty {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await vm.word(uniqe: uniqe)
            }
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
        guard let interstitialAdManager = interstitialAdManager, interstitialAdManager.interstitialAdLoaded else { return }
        interstitialAdManager.displayInterstitialAd { initalConfigirationForWord() }
    }
    
    private func initializeAI() {
        guard vm.aiDownloaded && ai == nil else { return }
        guard let lang   = language, let language = Language(rawValue: lang) else { return }
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
        
        phraseTask?.cancel()
        phraseTask = Task.detached(priority: .high) {
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { ai.startShowingPhrase() }
        }
    }
    
    @MainActor
    private func onAiWriting(myToken: UUID) -> Bool {
        return !Task.isCancelled && myToken == aiTypeToken
    }
    
    private func getAiWord() {
        guard let ai else { return }
        let row = current
        let aiDifficulty = aiDifficulty
        var arr = [String](repeating: "", count: length)
        aiTypeToken = UUID()
        let myToken = aiTypeToken
        
        Task.detached(priority: .high) {
            guard let aiWord = await ai.getFeedback(for: aiDifficulty)?.capitalizedFirst.toArray() else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            for i in 0..<aiWord.count {
                guard await onAiWriting(myToken: myToken) else { return }
                arr[i] = aiWord[i].returnChar(isFinal: i == aiWord.count - 1)
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard await onAiWriting(myToken: myToken) else { return }
                await MainActor.run {
                    guard guardVisible() else { return }
                    if aiMatrix.indices.contains(row) {
                        aiMatrix[row] = arr
                    }
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
            Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    audio.playSound(sound: "success", type: "wav")
                    makeHitOnAI(hitPoints: rows * hitPoints - current * hitPoints)
                    guard aiDifficultyPanding == aiDifficulty else { return }
                    Task(priority: .userInitiated) {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard let uniqe, guardVisible() else { return }
                        await vm.word(uniqe: uniqe)
                    }
                }
            }
        } else {
            if current == rows - 1 {
                delayedTurnTask?.cancel()
                delayedTurnTask = Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard guardVisible() else { return }
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
            Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    audio.playSound(sound: "fail", type: "wav")
                    makeHitOnPlayer(hitPoints: rows * hitPoints - current * hitPoints)
                    guard aiDifficultyPanding == aiDifficulty else { return }
                    Task(priority: .userInitiated) {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        animatedTurnSwitch(to: .player)
                        guard let uniqe, guardVisible() else { return }
                        await vm.word(uniqe: uniqe)
                    }
                }
            }
        }
        else if current < rows - 1 { current = i + 1 }
        else if current == rows - 1 {
            Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    audio.playSound(sound: "fail", type: "wav")
                    makeHitOnPlayer(hitPoints: noGuessHitPoints)
                    makeHitOnAI(hitPoints: noGuessHitPoints)
                    guard aiDifficultyPanding == aiDifficulty else { return }
                    Task(priority: .userInitiated) {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        animatedTurnSwitch(to: .player)
                        guard let uniqe, guardVisible() else { return }
                        await vm.word(uniqe: uniqe)
                    }
                }
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
            .onAppear { initializeAI(); isVisible = true }
            .onDisappear {
                isVisible = false
                screenManager.keepScreenOn = false
                audio.stop()
            }
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
                
                TurnChangeOverlay(isPresented: $turnFX.show,
                                  isAI: turnFX.next == .ai,
                                  language: language)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: aiDifficulty, handleAiIntroToggle)
        .onChange(of: endFetchAnimation, handleEndFetchAnimation)
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
    
    // MARK: - Sleek AI Intro (centered with tuned timing)
    @ViewBuilder private func aiIntro() -> some View {
        let accent = aiDifficulty.color
        ZStack {
            RadialGradient(
                colors: [Color.dynamicWhite.opacity(0.86), Color.dynamicWhite.opacity(0.95)],
                center: .center, startRadius: 24, endRadius: 700
            )
            .overlay(NoiseOverlay(opacity: 0.06))
            .circleReveal(trigger: $showAiIntro)
            .ignoresSafeArea()
            
            ZStack {
                // Stage 1: bokeh
                BokehField(accent: accent, isActive: showAiIntro)
                    .opacity(showAiIntro ? 1 : 0)
                    .animation(IntroAnim.bokeh, value: showAiIntro)
                    .allowsHitTesting(false)
                
                VStack(spacing: 20) {
                    // Stage 2: title
                    ShimmerText(
                        aiDifficulty.name.localized,
                        accent: accent,
                        font: .system(.largeTitle, design: .rounded).weight(.heavy),
                        baseOpacity: 0.9,
                        isActive: showAiIntro
                    )
                    .opacity(showAiIntro ? 1 : 0)
                    .animation(IntroAnim.title, value: showAiIntro)
                    
                    // Stage 3: avatar + ring settle
                    ZStack {
                        AnimatedAccentRing(accent: accent,
                                           diameter: 260,
                                           lineWidth: 12,
                                           rotationDuration: IntroAnim.ringRotateDuration)
                        .opacity(0.92)
                        .blur(radius: 0.25)
                        
                        OrbitingDots(accent: accent,
                                     radius: 145,
                                     dotSize: 6,
                                     count: 5,
                                     rotationDuration: IntroAnim.orbitRotateDuration)
                        
                        Image(aiDifficulty.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 220, height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .glassCard()
                .opacity(showAiIntro ? 1 : 0)
                .scaleEffect(showAiIntro ? 1.0 : 0.96)
                .animation(IntroAnim.card, value: showAiIntro)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder private func gameTopView() -> some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .top) {
                ZStack(alignment: .trailing) {
                    HStack {
                        Spacer()
                        ZStack(alignment: .center) {
                            EmptyCard(height: 76)
                                .realisticCell(color: .dynamicBlack.opacity(0.4), cornerRadius: 8)
                                .frame(width: 112)
                            VStack(spacing: 4) {
                                ZStack {
                                    Image("player_\(gender)")
                                        .resizable()
                                        .scaledToFill()
                                        .shadow(radius: 4)
                                        .frame(width: 50, height: 50)
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
                                        .scaleEffect(.init(width: playerHpAnimation.scale, height: playerHpAnimation.scale))
                                        .offset(x: playerHpAnimation.scale > 0 ? (language == "he" ? 12 : -12) : 0, y: playerHpAnimation.offset)
                                        .blur(radius: 0.5)
                                        .fixedSize()
                                }
                            }
                            .padding(.top, 2)
                            .padding(.bottom, 2)
                        }
                        .opacity(turn == .player ? 1 : 0.4)
                        
                        Spacer()
                        
                        ZStack(alignment: .center) {
                            EmptyCard(height: 76)
                                .realisticCell(color: .dynamicBlack.opacity(0.4), cornerRadius: 8)
                                .opacity(turn == .ai ? 1 : 0.4)
                                .frame(width: 112)
                            VStack(spacing: 4) {
                                ZStack {
                                    Image(aiDifficultyShow.image)
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
                                        .scaleEffect(.init(width: aiHpAnimation.scale, height: aiHpAnimation.scale))
                                        .offset(x: aiHpAnimation.scale > 0 ? (language == "he" ? 12 : -12) : 0, y: aiHpAnimation.offset)
                                        .blur(radius: 0.5)
                                        .fixedSize()
                                }
                                .opacity(turn == .ai ? 1 : 0.4)
                            }
                            .padding(.top, 2)
                            .padding(.bottom, 2)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.vertical)
            }
            .shadow(radius: 4)
        }
        .padding(.top, -15)
        .padding(.bottom, -20)
    }
    
    @ViewBuilder
    func EmptyCard(
        height: CGFloat = 120,
        cornerRadius: CGFloat = 8,
        borderColor: Color = .black.opacity(0.10),
        borderWidth: CGFloat = 1,
    ) -> some View {
        let background: LinearGradient = LinearGradient(
            colors: scheme == .light
            ? [
                Color(red: 0.98, green: 0.99, blue: 1.00),
                Color(red: 0.96, green: 0.98, blue: 1.00),
                Color(red: 0.99, green: 0.97, blue: 1.00)
            ]
            : [
                Color(red: 0.05, green: 0.06, blue: 0.09),
                Color(red: 0.07, green: 0.08, blue: 0.14),
                Color(red: 0.09, green: 0.08, blue: 0.17)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(background)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        borderColor,
                        style: StrokeStyle(lineWidth: borderWidth)
                    )
            )
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    @ViewBuilder private func gameTable() -> some View {
        ForEach(0..<rows, id: \.self) { i in
            ZStack {
                switch turn {
                case .player:
                    let hasPrevAIGuess = i > 0 && current == i && aiMatrix[current - 1].contains { !$0.isEmpty }
                    let placeHolderData = hasPrevAIGuess ? allBestGuesses : nil
                    let gainFocus = Binding(get: { endFetchAnimation && aiIntroDone && current == i }, set: { _ in })
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
                    .cardFlip(degrees: 180)
                }
            }
            .boardFlip(isAI: turn == .ai)
        }
    }
    
    @ViewBuilder private func gameBottom() -> some View {
        ZStack {
            KeyboardHeightView(adjustBy: 10)
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
        .padding(.bottom, -10)
        .frame(maxHeight: .infinity)
        .ignoresSafeArea(.keyboard)
    }
    
    @ViewBuilder private func game() -> some View {
        if let uniqe {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) { gameBody() }
                    .ignoresSafeArea(.keyboard)
                    .onAppear { onAppear(uniqe: uniqe) }
                    .onChange(of: vm.numberOfErrors, handleError)
                    .onChange(of: vm.word, handleWordChange)
                    .disabled(!endFetchAnimation || !didStart || vm.numberOfErrors > 0)
                    .opacity(endFetchAnimation && didStart && vm.numberOfErrors == 0 ? 1 : 0.7)
                    .grayscale(endFetchAnimation && didStart && vm.numberOfErrors == 0 ? 0 : 1)
            }
            .padding(.top, 44)
        }
    }
    
    @ViewBuilder private func overlayViews() -> some View {
        if endFetchAnimation { aiIntro() }
    }
    
    @ViewBuilder func backButton() -> some View {
        BackButton(action: backButtonTap)
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

// MARK: - Intro animation constants
fileprivate enum IntroAnim {
    static let bokeh  = Animation.easeOut(duration: 0.60).delay(0.05)
    static let title  = Animation.easeOut(duration: 0.50).delay(0.12)
    static let card   = Animation.spring(response: 0.55, dampingFraction: 0.88, blendDuration: 0.15)
    
    static let ringRotateDuration: Double  = 12  // slower, premium
    static let orbitRotateDuration: Double = 10  // slower, premium
}

// MARK: - Visual helpers used by AI Intro

fileprivate struct NoiseOverlay: View {
    var opacity: Double = 0.05
    var body: some View {
        Canvas { ctx, size in
            let count = Int((size.width * size.height) / 1400)
            for _ in 0..<count {
                let x = Double.random(in: 0...size.width)
                let y = Double.random(in: 0...size.height)
                let r = Double.random(in: 0.3...0.9)
                let p = Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r))
                ctx.fill(p, with: .color(.white.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
        .blendMode(.softLight)
        .opacity(opacity)
    }
}

fileprivate struct AnimatedAccentRing: View {
    var accent: Color
    var diameter: CGFloat = 240
    var lineWidth: CGFloat = 10
    var rotationDuration: Double = IntroAnim.ringRotateDuration
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t: CGFloat = 0
    
    var body: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(colors: [
                        accent.opacity(0.2),
                        accent.opacity(0.85),
                        accent.opacity(0.2)
                    ]),
                    center: .center
                ),
                lineWidth: lineWidth
            )
            .frame(width: diameter, height: diameter)
            .overlay { Circle().stroke(Color.white.opacity(0.07), lineWidth: 1) }
            .rotationEffect(.degrees(Double(t) * 360))
            .shadow(color: accent.opacity(0.35), radius: 18, y: 8)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: rotationDuration).repeatForever(autoreverses: false)) {
                    t = 1
                }
            }
    }
}

fileprivate struct OrbitingDots: View {
    var accent: Color
    var radius: CGFloat = 130
    var dotSize: CGFloat = 6
    var count: Int = 4
    var rotationDuration: Double = IntroAnim.orbitRotateDuration
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0
    
    var body: some View {
        TimelineView(.animation) { _ in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let p = (CGFloat(i) / CGFloat(count)) * .pi * 2 + phase
                    Circle()
                        .fill(accent.opacity(0.75))
                        .frame(width: dotSize, height: dotSize)
                        .shadow(color: accent.opacity(0.5), radius: 6)
                        .offset(x: cos(p) * radius, y: sin(p) * radius)
                        .blur(radius: 0.2)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: rotationDuration).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

fileprivate struct BokehField: View {
    var accent: Color
    var isActive: Bool = true
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seed: CGFloat = 0
    
    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                let count = 16
                for i in 0..<count {
                    let p = CGFloat(i) / CGFloat(count)
                    let r = CGFloat.lerp(24, 56, p) * (UIDevice.isPad ? 1.2 : 1.0)
                    let x = (CGFloat.hash(seed + p * 13).truncatingRemainder(dividingBy: 1)) * size.width
                    let y = (CGFloat.hash(seed + p * 29).truncatingRemainder(dividingBy: 1)) * size.height
                    let alpha = CGFloat.lerp(0.06, 0.22, abs(sin((seed + p) * 2)))
                    let rect = CGRect(x: x, y: y, width: r, height: r)
                    let path = Path(ellipseIn: rect)
                    ctx.fill(path, with: .radialGradient(
                        .init(colors: [accent.opacity(alpha), .clear]),
                        center: .init(x: rect.midX, y: rect.midY),
                        startRadius: 0, endRadius: r
                    ))
                }
            }
        }
        .opacity(0.9)
        .onAppear { startIfNeeded() }
        .onChange(of: isActive) { startIfNeeded() }
    }
    
    private func startIfNeeded() {
        guard !reduceMotion else { return }
        if isActive {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                seed = 1000 // advances hashes to “move”
            }
        } else {
            seed = 0
        }
    }
}

// (Optional) Kept for reference — not used now, but safe to keep.
// Parallax is NOT applied anywhere so intro stays centered.
fileprivate struct IntroParallax<C: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var x: CGFloat = 0
    @State private var y: CGFloat = 0
    let content: C
    init(@ViewBuilder content: () -> C) { self.content = content() }
    
    var body: some View {
        content
            .modifier(Parallax(x: x, y: y))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard !reduceMotion else { return }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            x = (v.location.x / UIScreen.main.bounds.width - 0.5) * 12
                            y = (v.location.y / UIScreen.main.bounds.height - 0.5) * 12
                        }
                    }
                    .onEnded { _ in
                        guard !reduceMotion else { return }
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                            x = 0; y = 0
                        }
                    }
            )
    }
    
    struct Parallax: ViewModifier {
        var x: CGFloat; var y: CGFloat
        func body(content: Content) -> some View {
            content
                .rotation3DEffect(.degrees(Double(x) * 0.4), axis: (x: 0, y: 1, z: 0))
                .rotation3DEffect(.degrees(Double(-y) * 0.4), axis: (x: 1, y: 0, z: 0))
                .offset(x: x * 0.3, y: y * 0.3)
        }
    }
}

fileprivate struct ShimmerText: View {
    var text: String
    var accent: Color
    var font: Font
    var baseOpacity: Double = 0.9
    var isActive: Bool = true
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1
    
    init(_ text: String, accent: Color, font: Font, baseOpacity: Double = 0.9, isActive: Bool = true) {
        self.text = text
        self.accent = accent
        self.font = font
        self.baseOpacity = baseOpacity
        self.isActive = isActive
    }
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(accent)
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.8), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: w * 0.35)
                    .offset(x: phase * (w + w * 0.35))
                    .blendMode(.screen)
                }
                .mask(Text(text).font(font))
            }
            .opacity(baseOpacity)
            .onAppear { runIfNeeded() }
            .onChange(of: isActive) { runIfNeeded() }
    }
    
    private func runIfNeeded() {
        guard !reduceMotion else { return }
        if isActive {
            withAnimation(.easeInOut(duration: 1.6).delay(0.18).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        } else {
            phase = -1
        }
    }
}

fileprivate extension View {
    func glassCard(cornerRadius: CGFloat = 28) -> some View {
        self
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            )
    }
}

fileprivate extension CGFloat {
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    static func hash(_ v: CGFloat) -> CGFloat {
        let s = sin(v * 12.9898) * 43758.5453
        return CGFloat(s - floor(s))
    }
}
