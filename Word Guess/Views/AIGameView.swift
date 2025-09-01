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

typealias HpAnimationParams =  (value: Int, opacity: CGFloat, scale: CGFloat, offset: CGFloat)

struct AIGameView<VM: WordViewModelForAI>: View {
    @EnvironmentObject private var coreData: PersistenceController
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    
    private enum Turn: Int  { case player = 0, ai = 1 }
    private enum GameState { case inProgress, lose, win }
    
    private let InterstitialAdInterval: Int = 7
    
    private let rows: Int = 5
    private var length: Int { DifficultyType.ai.getLength() }
    
    private var email: String? { loginHandeler.model?.email }
    private var gender: String? { loginHandeler.model?.gender }
    
    private let fullHP :Int = 100
    private let hitPoints = 10
    private let noGuessHitPoints = 40
    
    @State private var pack = AIPackManager()
    
    @State private var vm = VM()
    @State private var keyboard = KeyboardHeightHelper()
    @State private var endFetchAnimation = false
    @State private var didStart = false
    @State private var interstitialAdManager = InterstitialAdsManager(adUnitID: "GameInterstitial")
    
    @State private var aiHpAnimation: HpAnimationParams = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    @State private var playerHpAnimation: HpAnimationParams = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    
    @State private var disabled: Bool = false
    
    // player params
    @State private var current: Int = 0
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var playerHP: Int
    
    // ai params
    @State private var aiMatrix: [[String]]
    @State private var aiColors: [[CharColor]]
    @State private var aiHP: Int
    @State private var ai: WordleAIViewModel?
    @State private var showPhrase: Bool = false
    @State private var showAiIntro: Bool
    @State private var showGameEndPopup: Bool
    @State private var showExitPopup: Bool
    @State private var showCelebrate: Bool
    @State private var showMourn: Bool
    @State private var showError: Bool
    @State private var wordNumber = 0
    @State private var aiDifficulty: AIDifficulty {
        didSet {
            ai?.hidePhrase()
            UserDefaults.standard.set(aiDifficulty.rawValue.name, forKey: "aiDifficulty")
            Task(priority: .utility) { await SharedStore.writeAIStatsAsync(.init(name: aiDifficulty.rawValue.name, imageName:  aiDifficulty.rawValue.image)) }
        }
    }
    
    @State private var cleanCells = false
    
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
            case .player:
                let idx = current - 1
                guard idx >= 0,
                      aiMatrix.indices.contains(idx),
                      aiColors.indices.contains(idx) else { break }
                let guess   = aiMatrix[idx].joined()
                let pattern = aiColors[idx].map { $0.getColor() }.joined()
                ai?.saveToHistory(guess: (guess, pattern))

            case .ai:
                let idx = current
                guard matrix.indices.contains(idx),
                      colors.indices.contains(idx),
                      aiMatrix.indices.contains(idx),
                      aiMatrix[idx].allSatisfy(\.isEmpty) else { break }
                let guess   = matrix[idx].joined()
                let pattern = colors[idx].map { $0.getColor() }.joined()
                ai?.saveToHistory(guess: (guess, pattern))
            }
            
            guard turn == .ai else { return }
            
            Task(priority: .high) {
                guard let ai else { return }
                let row = current // snapshot to avoid races
                
                let aiWord = await ai.getFeedback(with: aiDifficulty)
                    .capitalizedFirst
                    .toArray()
                
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                
                var arr = [String](repeating: "", count: aiWord.count)
                for i in 0..<aiWord.count {
                    arr[i] = aiWord[i].returnChar(isFinal: i == aiWord.count - 1)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run {
                        if aiMatrix.indices.contains(row) {
                            aiMatrix[row] = arr
                        }
                    }
                }
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
                .map { $0.getColor() }   // <- call the method, not a key path
                .joined()
            return (s, pattern)
        }
    }
    
    private func handleWordChange() {
        initMatrixState()
        wordNumber += 1
        guard wordNumber % InterstitialAdInterval != 0 else {
            disabled = true
            return interstitialAdManager.loadInterstitialAd()
        }
        initalConfigirationForWord()
    }
    
    private func handleError() {
        guard !vm.fatalError else { return showError = true }
        guard vm.word == .empty && vm.numberOfErrors > 0 else { return }
        guard let email else { return closeViewAfterErorr() }
        Task(priority: .userInitiated) { await vm.word(email: email) }
    }
    
    private func handleStartup() async {
        await vm.word(email: loginHandeler.model!.email)
        didStart = vm.word != .empty
    }
    
    private func backButtonTap() {
        if endFetchAnimation { showExitPopup = true }
        else { closeView() }
    }
    
    private func closeView() {
        ai?.deassign()
        audio.stop()
        router.navigateBack()
    }
    
    private func closeViewAfterErorr() {
        keyboard.show = true
        closeView()
    }
    
    private func chackWord(index i: Int, matrix: [[String]]) -> Bool {
        let guess = matrix[i].joined()
        
        if guess.lowercased() == vm.word.value.lowercased() || i == rows - 1 {
            disabled = true
            audio.stop()
            
            let correct = guess.lowercased() == vm.word.value.lowercased()
            
            if correct {
                Task(priority: .userInitiated) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    //                    await MainActor.run { cleanCells = true }
                    guard let email else { return }
                    await vm.word(email: email)
                }
                
                return true
            }
            
            return false
        } else {
            disabled = turn == .player
            
            Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { withAnimation(.easeInOut(duration: 0.8)) { turn = .init(rawValue: 1 - turn.rawValue)! } }
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
        withAnimation(.easeInOut(duration: 0.6)) { turn = .player }
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
        
        self.showCelebrate = false
        
        self.showMourn = false
        
        self.showError = false
        
        self.current = 0
        
        self.aiHP = fullHP
        
        self.playerHP = fullHP
        
        self.turn = .player
        
        self.gameState = .inProgress
        
        let difficulty = UserDefaults.standard.string(forKey: "aiDifficulty")
        
#if DEBUG
        switch difficulty ?? AIDifficulty.easy.rawValue.name {
        case AIDifficulty.easy.rawValue.name: self.aiDifficulty = .easy
        case AIDifficulty.medium.rawValue.name: self.aiDifficulty = .medium
        case AIDifficulty.hard.rawValue.name: self.aiDifficulty = .hard
        case AIDifficulty.boss.rawValue.name: self.aiDifficulty = .boss
        default: fatalError()
        }
        //        self.aiDifficulty = .boss // change back to easy
#else
        switch difficulty ?? AIDifficulty.easy.rawValue.name {
        case AIDifficulty.easy.rawValue.name: self.aiDifficulty = .easy
        case AIDifficulty.medium.rawValue.name: self.aiDifficulty = .medium
        case AIDifficulty.hard.rawValue.name: self.aiDifficulty = .hard
        case AIDifficulty.boss.rawValue.name: self.aiDifficulty = .boss
        default: fatalError()
        }
#endif
    }
    
    private func aiIntroToggle() {
        Task.detached(priority: .userInitiated) {
            await MainActor.run { withAnimation(.easeInOut(duration: 2.5)) { showAiIntro = true } }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { withAnimation(.easeInOut(duration: 1.5)) { showAiIntro = false } }
        }
    }
    
    private func handleAi() {
        guard playerHP > 0 else { return }
        guard aiHP == 0 else { return }
        switch aiDifficulty {
        case .easy: withAnimation { aiDifficulty = .medium }
        case .medium: withAnimation { aiDifficulty = .hard }
        case .hard: withAnimation { aiDifficulty = .boss }
        case .boss: gameState = .win
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
        guard interstitialAdManager.interstitialAdLoaded else { return }
        interstitialAdManager.displayInterstitialAd { initalConfigirationForWord() }
    }
    
    private func initializeAI() {
        guard vm.aiDownloaded && ai == nil else { return }
        guard let lang = language,
              let language = Language(rawValue: lang) else { return }
        ai = .init(language: language)
    }
    
    private func handlePhrase() { showPhrase = ai?.showPhraseValue ?? false }
    
    private func handleAiIntroToggle<T: Equatable>(oldValue: T, newValue: T) {
        guard oldValue != newValue && (!(type(of: newValue) is Bool.Type) || (newValue as! Bool)) else { return }
        aiIntroToggle()
    }
    
    private func handleEndFetchAnimation<T: Equatable>(oldValue: T, newValue: T) {
        handleAiIntroToggle(oldValue: oldValue, newValue: newValue)
        Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            ai?.startShowingPhrase()
        }
    }
    
    private func calculatePlayerTurn(i: Int) {
        guard i == current else { return }
        colors[i] = vm.calculateColors(with: matrix[i])
        
        if chackWord(index: i, matrix: matrix) { makeHitOnAI(hitPoints: rows * hitPoints - current * hitPoints) }
        else if current == rows - 1 {
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { withAnimation(.easeInOut(duration: 0.6).delay(0.5)) { turn = .ai } }
            }
        }
    }
    
    private func calculateAITurn(i: Int) {
        guard i == current else { return }
        aiColors[i] = vm.calculateColors(with: aiMatrix[i])
        
        if chackWord(index: i, matrix: aiMatrix) { makeHitOnPlayer(hitPoints: rows * hitPoints - current * hitPoints) }
        else if current < rows - 1 { current = i + 1 }
        else if current == rows - 1 {
            makeHitOnPlayer(hitPoints: noGuessHitPoints)
            makeHitOnAI(hitPoints: noGuessHitPoints)
            Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                //                await MainActor.run { cleanCells = true }
                guard let email else { return }
                await vm.word(email: email)
            }
        }
    }
    
    private func initalConfigirationForWord() {
        Task(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: (keyboard.show ? 0 : 500_000_000))
            audio.playSound(sound: "backround",
                            type: "mp3",
                            loop: true)
            
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { endFetchAnimation = true }
        }
        
        disabled = false
        current = 0
        ai?.addDetachedFirstGuess(with: firstGuess)
    }
    
    var body: some View {
        ZStack {
            if let ai, ai.isReadyToGuess { contant() }
            else if vm.aiDownloaded { AIPackLoadingView(onCancel: router.navigateBack) }
            else { AIPackDownloadView(downloaded: $vm.aiDownloaded,
                                      onCancel: router.navigateBack) }
        }
        .onChange(of: vm.aiDownloaded, initializeAI)
        .onChange(of: ai?.showPhraseValue, handlePhrase)
    }
    
    @ViewBuilder private func contant() -> some View {
        GeometryReader { proxy in
            background()
            ZStack(alignment: .top) {
                topBar()
                game(proxy: proxy)
                overlayViews(proxy: proxy)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: aiDifficulty, handleAiIntroToggle)
        .onChange(of: endFetchAnimation, handleEndFetchAnimation)
        .onChange(of: interstitialAdManager.interstitialAdLoaded, handleInterstitial)
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
                     action: closeView,
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
            AdView(adUnitID: "GameBanner")
        }
    }
    
    @ViewBuilder private func background() -> some View {
        LinearGradient(colors: [.red,
                                .yellow,
                                .green,
                                .blue],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
        .blur(radius: 4)
        .opacity(0.1)
        .ignoresSafeArea()
    }
    
    @ViewBuilder private func aiIntro() -> some View {
        ZStack {
            Color.white
                .circleReveal(trigger: $showAiIntro)
                .ignoresSafeArea()
            
            VStack {
                Text(aiDifficulty.rawValue.name.localized)
                    .font(.largeTitle)
                    .foregroundStyle(aiDifficulty.rawValue.color)
                
                Image(aiDifficulty.rawValue.image)
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
    
    @ViewBuilder private func gameBody(proxy: GeometryProxy) -> some View {
        if !vm.fatalError && didStart {
            VStack(spacing: 8) {
                ZStack(alignment: .bottom) {
                    ZStack(alignment: .top) {
                        ZStack(alignment: .trailing) {
                            HStack {
                                Spacer()
                                VStack {
                                    Image("player_\(gender ?? "male")")
                                        .resizable()
                                        .scaledToFill()
                                        .shadow(radius: 4)
                                        .frame(width: 50, height: 50)
                                        .opacity(turn == .player ? 1 : 0.4)
                                    
                                    ZStack {
                                        HPBar(value: Double(playerHP),
                                              maxValue: Double(fullHP))
                                        .frame(width: 100)
                                        
                                        Text("- \(playerHpAnimation.value)")
                                            .font(.body.weight(.heavy))
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity)
                                            .foregroundStyle(.red)
                                            .opacity(playerHpAnimation.opacity)
                                            .scaleEffect(.init(width: playerHpAnimation.scale,
                                                               height: playerHpAnimation.scale))
                                            .offset(x: playerHpAnimation.scale > 0 ? language == "he" ? 12 : -12 : 0,
                                                    y: playerHpAnimation.offset)
                                            .blur(radius: 0.5)
                                            .fixedSize()
                                    }
                                    .padding(.bottom, 5)
                                }
                                
                                Spacer()
                                
                                VStack {
                                    Image(aiDifficulty.rawValue.image)
                                        .resizable()
                                        .scaledToFill()
                                        .shadow(radius: 4)
                                        .frame(width: 50, height: 50)
                                        .opacity(turn == .ai ? 1 : 0.4)
                                        .tooltip(ai!.phrase,
                                                 language: language == "he" ? .he : .en,
                                                 trigger: .manual,
                                                 isPresented: $showPhrase)
                                    
                                    ZStack {
                                        HPBar(value: Double(aiHP),
                                              maxValue: Double(fullHP))
                                        .frame(width: 100)
                                        
                                        Text("- \(aiHpAnimation.value)")
                                            .font(.body.weight(.heavy))
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity)
                                            .foregroundStyle(.red)
                                            .opacity(aiHpAnimation.opacity)
                                            .scaleEffect(.init(width: aiHpAnimation.scale,
                                                               height: aiHpAnimation.scale))
                                            .offset(x: aiHpAnimation.scale > 0 ? language == "he" ? 12 : -12 : 0,
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
                .padding(.top, -10)
                .padding(.bottom, -20)
                
                ForEach(0..<rows, id: \.self) { i in
                    ZStack {
                        switch turn {
                        case .player:
                            let hasPrevAIGuess = i > 0 && current == i && aiMatrix[current - 1].contains { !$0.isEmpty }
                            let placeHolderData = hasPrevAIGuess ? allBestGuesses : nil
                            let gainFocus = Binding(get: { current == i }, set: { _ in })
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
                            .rotation3DEffect(.degrees(turn == .ai ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                            
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
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                        }
                    }
                    .rotation3DEffect(.degrees(turn == .ai ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                }
                
                if endFetchAnimation {
                    AppTitle()
                        .padding(.top, 90)
                        .padding(.bottom, 150)
                        .shadow(radius: 4)
                } else {
                    ZStack{}
                        .frame(height: 81)
                        .padding(.top, 90)
                        .padding(.bottom, 150)
                        .shadow(radius: 4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, -10)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)
        }
    }
    
    @ViewBuilder private func game(proxy: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) { gameBody(proxy: proxy) }
                .ignoresSafeArea(.keyboard)
                .task { await handleStartup() }
                .onChange(of: vm.numberOfErrors, handleError)
                .onChange(of: vm.word, handleWordChange)
                .ignoresSafeArea(.keyboard)
        }
        .padding(.top, 64)
    }
    
    @ViewBuilder private func overlayViews(proxy: GeometryProxy) -> some View {
        if !vm.fatalError && !endFetchAnimation && !keyboard.show { FetchingView(word: vm.wordValue) }
        else { aiIntro() }
    }
    
    @ViewBuilder func backButton() -> some View {
        HStack {
            BackButton(action: backButtonTap)
                .padding(.top, 20)
            Spacer()
        }
        .padding(.bottom, 20)
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
            ? index(after: found.lowerBound)   // step 1 char → allows overlaps
            : found.upperBound                 // skip past match → non-overlapping
            searchRange = nextStart..<endIndex
        }
        return count
    }
}


//#Preview {
//    AIGameView()
//        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
//}
