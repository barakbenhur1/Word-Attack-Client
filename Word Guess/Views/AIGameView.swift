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
    
    private let queue = DispatchQueue.main
    
    private let InterstitialAdInterval: Int = 7
    
    private let rows: Int = 5
    private var length: Int { DifficultyType.ai.getLength() }
    private var email: String? { loginHandeler.model?.email }
    private var gender: String? { loginHandeler.model?.gender }
    
    private let fullHP :Int = 100
    private let hitPoints = 5
    private let noGuessHitPoints = 10
    
    @State private var pack = AIPackManager()
    
    @State private var vm = VM()
    @State private var keyboard = KeyboardHeightHelper()
    @State private var endFetchAnimation = false
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
    @State private var aiDfficulty: AIDifficulty
    @State private var showGameEndPopup: Bool
    @State private var showExitPopup: Bool
    @State private var showCelebrate: Bool
    @State private var showMourn: Bool
    @State private var wordNumber = 0
    
    @State private var cleanCells = false
    
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
            switch turn {
            case .player:
                guard current > 0 && aiMatrix.count > current - 1 else { break }
                ai?.saveToHistory(guess: (aiMatrix[current - 1].joined(), aiColors[current - 1].map { $0.getColor() }.joined()))
            case .ai:
                guard aiMatrix.count > current && aiMatrix[current].filter({ !$0.isEmpty }).isEmpty else { break }
                ai?.saveToHistory(guess: (matrix[current].joined(), colors[current].map { $0.getColor() }.joined()))
            }
            
            guard turn == .ai else { return }
            Task(priority: .high) {
                guard let ai else { return }
                let aiWord = await ai.getFeedback(with: aiDfficulty).capitalizedFirst.toArray()
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
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    private var firstGuess: (_ string: String) -> GuessHistory { { string in return (string, vm.calculateColors(with: string.map { "\($0)" }, length: length).map { $0.getColor() }.joined()) } }
    
    private var allBestGuesses: [BestGuess] { return vm.perIndexCandidatesSparse(matrix: matrix,
                                                                     colors: colors,
                                                                     aiMatrix: aiMatrix,
                                                                     aiColors: aiColors) }
    
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
        guard vm.isError else { return }
        keyboard.show = true
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
        Task.detached(priority: .userInitiated) {
            await MainActor.run { withAnimation(.easeInOut(duration: 2.5)) { showAiIntro = true } }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { withAnimation(.easeInOut(duration: 1.5)) { showAiIntro = false } }
        }
    }
    
    private func handleAiHp() {
        guard playerHP > 0 else { return }
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
    
    private func calculatePlayerTurn(i: Int) {
        guard i == current else { return }
        colors[i] = vm.calculateColors(with: matrix[i],
                                 length: length)
       
        if chackWord(i: i, matrix: matrix) { makeHitOnAI(hitPoints: rows * hitPoints - current * hitPoints) }
        if current == rows - 1 {
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.6).delay(0.5)) {
                        turn = .ai
                    }
                }
            }
        }
    }
    
    private func calculateAITurn(i: Int) {
        guard i == current else { return }
        aiColors[i] = vm.calculateColors(with: aiMatrix[i],
                                   length: length)
        
        if chackWord(i: i, matrix: aiMatrix) { makeHitOnPlayer(hitPoints: rows * hitPoints - current * hitPoints) }
        else if current < rows - 1 { current = i + 1 }
        else if current == rows - 1 {
            makeHitOnPlayer(hitPoints: noGuessHitPoints)
            makeHitOnAI(hitPoints: noGuessHitPoints)
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { cleanCells = true }
            }
            Task.detached(priority: .userInitiated) { await vm.word(email: loginHandeler.model!.email) }
        }
    }
    
    var body: some View {
        ZStack {
            if let ai, ai.isReadyToGuess { contant() }
            else if vm.aiDownloaded { AIPackLoadingView(onCancel: { router.navigateBack() }) }
            else { AIPackDownloadView(downloaded: $vm.aiDownloaded,
                                      onCancel: { router.navigateBack() }) }
        }
        .onChange(of: vm.aiDownloaded, initializeAI)
        .onChange(of: ai?.showPhrase, { showPhrase = ai?.showPhrase ?? false })
    }
    
    @ViewBuilder private func aiIntro() -> some View {
        ZStack {
            Color.white
                .circleReveal(trigger: $showAiIntro)
                .ignoresSafeArea()
            
            VStack {
                Text(aiDfficulty.rawValue.name.localized)
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
        if !vm.isError && vm.word != .empty {
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
                                }
                                
                                Spacer()
                                
                                VStack {
                                    Image(aiDfficulty.rawValue.image)
                                        .resizable()
                                        .scaledToFill()
                                        .shadow(radius: 4)
                                        .frame(width: 50, height: 50)
                                        .opacity(turn == .ai ? 1 : 0.4)
//                                        .tooltip(showPhrase,
//                                                 side: language == "he" ? .right : .left) {
//                                            Text(ai!.phrase)
//                                                .lineLimit(1)
//                                                .truncationMode(.tail)
//                                                .frame(width: 80, alignment: .leading)   // hard cap at 80pt
//                                                .allowsTightening(true)                  // nicer squeeze before ellipsis
//                                        }
                                    
                                    ZStack {
                                        Text("HP: \(aiHP)")
                                            .font(.body.bold())
                                            .foregroundStyle(aiHP <= 40 ? .red : aiHP <= 80 ? .orange : .green)
                                            .animation(.easeInOut, value: aiHP)
                                        
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
                            WordView(clenCells: $cleanCells,
                                     current: $current,
                                     length: length,
                                     placeHolderData: i > 0 && current == i && !aiMatrix[current - 1].filter({ s in !s.isEmpty }).isEmpty ? allBestGuesses : nil,
                                     word: $matrix[i],
                                     gainFocus: .constant(!showAiIntro && endFetchAnimation),
                                     colors: $colors[i],
                                     done: { calculatePlayerTurn(i: i) })
                            .disabled(disabled || current != i)
                            .shadow(radius: 4)
                            .rotation3DEffect(.degrees(turn == .ai ? 180 : 0),
                                              axis: (x: 0, y: 1, z: 0))
                            
                        case .ai:
                            WordView(clenCells: $cleanCells,
                                     isAI: true,
                                     current: $current,
                                     length: length,
                                     isCurrentRow: current == i && !matrix[current].filter({ s in !s.isEmpty }).isEmpty,
                                     word: $aiMatrix[i],
                                     gainFocus: .constant(false),
                                     colors: $aiColors[i],
                                     done: { calculateAITurn(i: i) })
                            .disabled(true)
                            .shadow(radius: 4)
                            .rotation3DEffect(.degrees(180),
                                              axis: (x: 0, y: 1, z: 0))
                            
                        }
                    }
                    .rotation3DEffect(.degrees(turn == .ai ? 180 : 0),
                                      axis: (x: 0, y: 1, z: 0))
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
                .task { await vm.word(email: loginHandeler.model!.email) }
                .onChange(of: vm.isError, handleError)
                .onChange(of: vm.word, handleWordChange)
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
        ai?.addDetachedFirstGuess(with: firstGuess)
        queue.asyncAfter(deadline: .now() + 2) { endFetchAnimation = true }
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
        
        if guess.lowercased() == vm.word.value.lowercased() || i == rows - 1 {
            disabled = true
            audio.stop()
            
            let correct = guess.lowercased() == vm.word.value.lowercased()
            
            if correct {
                Task.detached(priority: .userInitiated) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await MainActor.run { cleanCells = true }
                }
                
                Task(priority: .userInitiated) {
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
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        turn = .init(rawValue: 1 - turn.rawValue)!
                    }
                }
            }
            
            return false
        }
    }
    
    private func makeHitOnPlayer(hitPoints: Int) { makeHit(hp: $playerHP, hpParams: $playerHpAnimation, hitPoints: hitPoints) }
    private func makeHitOnAI(hitPoints: Int) { makeHit(hp: $aiHP, hpParams: $aiHpAnimation, hitPoints: hitPoints) }
    private func makeHit(hp: Binding<Int>, hpParams: Binding<HpAnimationParams>, hitPoints: Int) {
        current = .max
        
        hpParams.wrappedValue.value = hitPoints
        
        withAnimation(.linear(duration: 1.4)) {
            hpParams.wrappedValue.offset = -30
            hpParams.wrappedValue.opacity = 1
            hpParams.wrappedValue.scale = 1.6
        }
        
        queue.asyncAfter(deadline: .now() + 1.44) {
            guard hpParams.wrappedValue.opacity == 1 else { return }
            withAnimation(.linear(duration: 0.4)) {
                hpParams.wrappedValue.opacity = 0
                hpParams.wrappedValue.scale = 0
                let newHP = hp.wrappedValue - hitPoints
                hp.wrappedValue = max(0, newHP)
            }
            
            queue.asyncAfter(deadline: .now() + 0.4) {
                hpParams.wrappedValue.value = 0
                hpParams.wrappedValue.offset = 30
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
        
        cleanCells = false
        
        turn = .player
        
        ai?.cleanHistory()
        
        switch aiDfficulty {
        case .boss: WordleAI.installCheatAnswerProvider( { vm.word.value } )
        default: break
        }
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
