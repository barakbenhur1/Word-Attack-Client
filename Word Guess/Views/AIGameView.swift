//
//  AIGameView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 04/08/2025.
//

import SwiftUI
import CoreData
import Combine

typealias HpAnimationPArams =  (value: Int, opticity: CGFloat, scale: CGFloat, offset: CGFloat)

struct AIGameView<VM: ViewModel>: View {
    @EnvironmentObject private var coreData: PersistenceController
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    
    private enum Turn: Int {
        case player = 0, ai = 1
    }
    
    private enum GameState {
        case inProgress, lose, win
    }
    
    private let queue = DispatchQueue.main
    private let InterstitialAdInterval: Int = 7
    private let fullHP :Int = 100
    private let rows: Int = 5
    private var length: Int { return DifficultyType.ai.getLength() }
    private var email: String? { return loginHandeler.model?.email }
    private var gender: String? { return loginHandeler.model?.gender }
    
    @State private var pack = AIPackManager()

    @State private var vm = VM()
    @State private var keyboard = KeyboardHeightHelper()
    @State private var endFetchAnimation = false
    @State private var interstitialAdManager = InterstitialAdsManager(adUnitID: "GameInterstitial")
    
    @State private var aiHpAnimation: HpAnimationPArams = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    @State private var playerHpAnimation: HpAnimationPArams = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    
    @State private var disabled: Bool = false
    
    // player
    @State private var current: Int = 0 { didSet { vm.current = current } }
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var playerHP: Int
    
    // ai
    @State private var aiMatrix: [[String]]
    @State private var aiColors: [[CharColor]]
    @State private var aiHP: Int
    @State private var ai: WordleAIViewModel?
    @State private var showAiIntro: Bool
    @State private var aiDfficulty: AIDifficulty
    @State private var showGameEndPopup: Bool
    @State private var showExitPopup: Bool
    @State private var showCelebrate: Bool
    @State private var showMourn: Bool
    @State private var wordNumber = 0
   
    @State private var gameState: GameState {
        didSet {
            switch gameState {
            case .inProgress: break
            case .lose: showMourn = true
            case .win: showCelebrate = true
            }
        }
    }
    
    @State private var turn: Turn {
        didSet {
            guard turn == .ai else { return }
            Task(priority: .high) {
                guard let ai else { return }
                let aiWord = await ai.submitFeedback(guess: bestGuessFormatted,
                                                     difficulty: aiDfficulty).capitalizedFirst.toArray()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                var arr = [String](repeating: "", count: aiWord.count)
                for i in 0..<aiWord.count {
                    arr[i] = aiWord[i].returnChar(isFinal: i == aiWord.count - 1)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    aiMatrix[current] = arr
                }
            }
        }
    }
    
    private let hitPoints = 20
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    private var firstGuess: (_ string: String) -> GuessHistory { { string in return (string, vm.calcGuess(word: string.map { "\($0)" }, length: length).map { $0.getColor() }.joined()) } }
    
    private var allBestGuesses: [[Guess]] { return vm.allBestGuesses(matrix: matrix,
                                                                     colors: colors,
                                                                     aiMatrix: aiMatrix,
                                                                     aiColors: aiColors) }
    
    private var cleanBestGuess: [[Guess]]? {
        let bestGuess = allBestGuesses.filter { guess in !guess.filter { char, color in char != " " && color != .noGuess }.isEmpty }
        return bestGuess.isEmpty ? nil : bestGuess
    }
    
    private var bestGuessFormatted: [GuessHistory] {
        var guess = [GuessHistory]()
        cleanBestGuess?.forEach { g in guess.append((g.map(\.char).joined(), g.map{ $0.color.getColor() }.joined())) }
        return guess
    }
    
    private var bestEntropyGuess: [[Guess]]? {
        guard let cleanBestGuess else { return nil }
        let arr = BestGuessProducerProvider.guesser.bestEntropyRow(from: cleanBestGuess)
        return arr != nil ? [arr!] : nil
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
        
        self.current = 0
        
        self.aiHP = fullHP
        
        self.playerHP = fullHP
        
        self.turn = .player
        
        self.gameState = .inProgress
        
#if DEBUG
        self.aiDfficulty = .boss // change back to easy
#else
        self.aiDfficulty = .easy
#endif
    }
    
    private func aiIntroToggle() {
        Task.detached {
            await MainActor.run { withAnimation(.easeInOut(duration: 2.5)) { showAiIntro = true } }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { withAnimation(.easeInOut(duration: 1.5)) { showAiIntro = false } }
        }
    }
    
    private func handleAiHp() {
        if aiHP == 0 {
            switch aiDfficulty {
            case .easy:
                aiDfficulty = .medium
                aiHP = fullHP
            case .medium:
                aiDfficulty = .hard
                aiHP = fullHP
            case .hard:
                aiDfficulty = .boss
                aiHP = fullHP
            case .boss: gameState = .win
            }
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
    
    private func handlePlayerHp() {
        guard playerHP == 0 else { return }
        gameState = .lose
    }
    
    private func handleInterstitial() {
        guard interstitialAdManager.interstitialAdLoaded else { return }
        interstitialAdManager.displayInterstitialAd { initalConfigirationForWord() }
    }
    
    private func initializeAI() {
        guard vm.aiDownloaded && ai == nil else { return }
//        AIHealthCheck.run(note: "post-gate")
        ai = .init(language: language == "he" ? .he : .en)
    }
    
    private func handleAiIntroToggle<T: Equatable>(oldValue: T, newValue: T) {
        guard oldValue != newValue && (!(type(of: newValue) is Bool.Type) || (newValue as! Bool)) else { return }
        aiIntroToggle()
    }
    
    var body: some View {
        ZStack {
            if let ai, ai.isReadyToGuess { contant() }
            else if vm.aiDownloaded { AIPackLoadingView(onCancel: { router.navigateBack() }) }
            else { AIPackDownloadView(downloaded: $vm.aiDownloaded,
                                      onCancel: { router.navigateBack() }) }
        }
        .onChange(of: vm.aiDownloaded, initializeAI)
    }
    
    @ViewBuilder private func aiIntro() -> some View {
        ZStack {
            Color.white
                .circleReveal(trigger: $showAiIntro)
                .ignoresSafeArea()
            
            VStack {
                Text(aiDfficulty.rawValue.name)
                    .font(.largeTitle)
                Image(aiDfficulty.rawValue.image)
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
    
    @ViewBuilder private func contant() -> some View {
        GeometryReader { proxy in
            background()
            ZStack(alignment: .top) {
                topBar()
                game(proxy: proxy)
                overlayViews(proxy: proxy)
                    .onChange(of: aiDfficulty, handleAiIntroToggle)
                    .onChange(of: endFetchAnimation, handleAiIntroToggle)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: interstitialAdManager.interstitialAdLoaded, handleInterstitial)
        .onChange(of: playerHP, handlePlayerHp)
        .onChange(of: aiHP, handleAiHp)
        .onChange(of: showCelebrate, handleWin)
        .onChange(of: showMourn, handleLose)
        .celebrate($showCelebrate)
        .mourn($showMourn)
        .customAlert("YOU vs AI",
                     type: gameState == .win ? .success : .fail,
                     isPresented: $showGameEndPopup,
                     actionText: "OK",
                     action: {
            audio.stop()
            router.navigateBack()
        }, message: { Text("You \(gameState == .win ? "win".localized : "lose".localized)") })
        .customAlert("Exit",
                     type: .info,
                     isPresented: $showExitPopup,
                     actionText: "OK",
                     cancelButtonText: "Cancel",
                     action: {
            audio.stop()
            router.navigateBack()
        }, message: { Text("By exiting you will lose all progress") })
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
    
    @ViewBuilder private func gameBody(proxy: GeometryProxy) -> some View {
        if !vm.isError && vm.word != .emapty {
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
                                        Text("HP: \(playerHP)")
                                            .font(.body.bold())
                                            .foregroundStyle(playerHP <= 40 ? .red : playerHP <= 80 ? .orange : .green)
                                            .animation(.easeInOut, value: playerHP)
                                        
                                        Text("- \(playerHpAnimation.value)")
                                            .font(.largeTitle.weight(.heavy))
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity)
                                            .foregroundStyle(.red)
                                            .opacity(playerHpAnimation.opticity)
                                            .scaleEffect(.init(width: playerHpAnimation.scale,
                                                               height: playerHpAnimation.scale))
                                            .offset(x: playerHpAnimation.scale > 0 ? language == "he" ? 12 : -12 : 0,
                                                    y: playerHpAnimation.offset)
                                            .blur(radius: 0.5)
                                            .fixedSize()
                                    }
                                    .padding(.top, -20)
                                }
                                
                                Spacer()
                                
                                VStack {
                                    Image(aiDfficulty.rawValue.image)
                                        .resizable()
                                        .scaledToFill()
                                        .shadow(radius: 4)
                                        .frame(width: 50, height: 50)
                                        .opacity(turn == .ai ? 1 : 0.4)
                                    
                                    ZStack {
                                        Text("HP: \(aiHP)")
                                            .font(.body.bold())
                                            .foregroundStyle(aiHP <= 40 ? .red : aiHP <= 80 ? .orange : .green)
                                            .animation(.easeInOut, value: aiHP)
                                        
                                        Text("- \(aiHpAnimation.value)")
                                            .font(.largeTitle.weight(.heavy))
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity)
                                            .foregroundStyle(.red)
                                            .opacity(aiHpAnimation.opticity)
                                            .scaleEffect(.init(width: aiHpAnimation.scale,
                                                               height: aiHpAnimation.scale))
                                            .offset(x: aiHpAnimation.scale > 0 ? language == "he" ? 12 : -12 : 0,
                                                    y: aiHpAnimation.offset)
                                            .blur(radius: 0.5)
                                            .fixedSize()
                                    }
                                    .padding(.top, -20)
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
                            WordView(length: length,
                                     placeHolderData: i > 0 && current == i && !aiMatrix[current - 1].filter({ s in !s.isEmpty }).isEmpty ? cleanBestGuess : nil,
                                     word: $matrix[i],
                                     gainFocus: .constant(!showAiIntro && endFetchAnimation),
                                     colors: $colors[i]) {
                                guard i == current else { return }
                                colors[i] = vm.calcGuess(word: matrix[i],
                                                         length: length)
                                if chackWord(i: i, matrix: matrix) { makeHitOnAI() }
                                
                                if current == rows - 1 {
                                    Task.detached {
                                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                                        await MainActor.run {
                                            withAnimation(.easeInOut(duration: 0.6).delay(0.5)) {
                                                turn = .ai
                                            }
                                        }
                                    }
                                }
                            }
                                     .disabled(disabled || current != i)
                                     .environmentObject(vm)
                                     .shadow(radius: 4)
                                     .rotation3DEffect(.degrees(turn == .ai ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                            
                        case .ai:
                            WordView(isAI: true,
                                     length: length,
                                     isCurrentRow: current == i && !matrix[current].filter({ s in !s.isEmpty }).isEmpty,
                                     word: $aiMatrix[i],
                                     gainFocus: .constant(false),
                                     colors: $aiColors[i]) {
                                guard i == current else { return }
                                aiColors[i] = vm.calcGuess(word: aiMatrix[i],
                                                           length: length)
                                if chackWord(i: i, matrix: aiMatrix) { makeHitOnPlayer() }
                                
                                if current < rows - 1 { current = i + 1 }
                                else if current == rows - 1 {
                                    Task.detached { await vm.wordForAiMode(email: loginHandeler.model!.email) }
                                }
                            }
                                     .disabled(true)
                                     .environmentObject(vm)
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
                .task { await vm.wordForAiMode(email: loginHandeler.model!.email) }
                .onChange(of: vm.isError) {
                    guard vm.isError else { return }
                    keyboard.show = true
                }
                .onChange(of: vm.word.word) {
                    initMatrixState()
                    wordNumber += 1
                    guard wordNumber % InterstitialAdInterval != 0 else {
                        disabled = true
                        return interstitialAdManager.loadInterstitialAd()
                    }
                    initalConfigirationForWord()
                }
                .ignoresSafeArea(.keyboard)
        }
        .padding(.top, 64)
    }
    
    private func initalConfigirationForWord() {
        queue.asyncAfter(deadline: .now() + (keyboard.show ? 0 : 0.5)) {
            audio.playSound(sound: "backround",
                            type: "mp3",
                            loop: true)
        }
        
        disabled = false
        current = 0
        ai?.addDetachedGuess(with: firstGuess)
        queue.asyncAfter(deadline: .now() + (keyboard.show ? 0 : 0.5)) { endFetchAnimation = true }
    }
    
    @ViewBuilder private func overlayViews(proxy: GeometryProxy) -> some View {
        if !vm.isError && !endFetchAnimation && !keyboard.show { FetchingView(vm: vm) }
        else { aiIntro() }
    }
    
    @ViewBuilder func backButton() -> some View {
        HStack {
            BackButton(action: { showExitPopup = true })
                .padding(.top, 20)
            Spacer()
        }
        .padding(.bottom, 20)
    }
    
    private func chackWord(i: Int, matrix: [[String]]) -> Bool {
        let guess = matrix[i].joined()
        
        if guess.lowercased() == vm.word.word.value.lowercased() || i == rows - 1 {
            disabled = true
            audio.stop()
            
            let correct = guess.lowercased() == vm.word.word.value.lowercased()
            
            if correct {
                current = .max
                Task {
                    guard let email else { return }
                    await vm.wordForAiMode(email: email)
                }
                
                return true
            }
            
            return false
            
        } else {
            disabled = turn == .player
            
            Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        turn = .init(rawValue: 1 - turn.rawValue)!
                    }
                }
            }
            
            return false
        }
    }
    
    private func makeHitOnPlayer() {
        playerHpAnimation.value = hitPoints
       
        withAnimation(.linear(duration: 0.8)) {
            playerHpAnimation.offset = 0
            playerHpAnimation.opticity = 1
            playerHpAnimation.scale = 0.9
        }
        
        queue.asyncAfter(deadline: .now() + 0.8) {
            guard playerHpAnimation.opticity == 1 else { return }
            
            withAnimation(.linear(duration: 0.2)) {
                playerHpAnimation.opticity = 0
                playerHpAnimation.scale = 0
                playerHP -= hitPoints
            }
            
            queue.asyncAfter(deadline: .now() + 0.2) {
                playerHpAnimation.value = 0
                playerHpAnimation.offset = 30
            }
        }
    }
    
    private func makeHitOnAI() {
        aiHpAnimation.value = hitPoints
       
        withAnimation(.linear(duration: 0.8)) {
            aiHpAnimation.offset = 0
            aiHpAnimation.opticity = 1
            aiHpAnimation.scale = 0.9
        }
        
        queue.asyncAfter(deadline: .now() + 0.8) {
            guard aiHpAnimation.opticity == 1 else { return }
            
            withAnimation(.linear(duration: 0.2)) {
                aiHpAnimation.opticity = 0
                aiHpAnimation.scale = 0
                aiHP -= hitPoints
            }
            
            queue.asyncAfter(deadline: .now() + 0.2) {
                aiHpAnimation.value = 0
                aiHpAnimation.offset = 30
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
        
        aiMatrix = [[String]](repeating: [String](repeating: "",
                                                  count: length),
                              count: rows)
        aiColors = [[CharColor]](repeating: [CharColor](repeating: .noGuess,
                                                        count: length),
                                 count: rows)
        
        turn = .player
        
        ai?.cleanHistory()
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).capitalized + dropFirst()
    }
    
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
