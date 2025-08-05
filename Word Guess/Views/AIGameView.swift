//
//  AIGameView.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 04/08/2025.
//

import SwiftUI
import CoreData
import Combine

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
    private let rows: Int = 5
    private var length: Int { return DifficultyType.roguelike.getLength() }
    private var email: String? { return loginHandeler.model?.email }
    
    @State private var vm = VM()
    @State private var keyboard = KeyboardHeightHelper()
    @State private var timeAttackAnimation = false
    @State private var timeAttackAnimationDone = true
    @State private var endFetchAnimation = false
    @State private var interstitialAdManager = InterstitialAdsManager(adUnitID: "GameInterstitial")
    
    @State private var aiHpAnimation: (value: Int, opticity: CGFloat, scale: CGFloat, offset: CGFloat) = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    @State private var playerHpAnimation: (value: Int, opticity: CGFloat, scale: CGFloat, offset: CGFloat) = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    
    @State private var disabled: Bool = false
    
    // player
    @State private var current: Int = 0 { didSet { vm.current = current } }
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var playerHP: Int = 100
    
    // ai
    @State private var aiMatrix: [[String]]
    @State private var aiColors: [[CharColor]]
    @State private var aiHP: Int = 100
    @State private var ai: WordleViewModel = .init(isHebrew: Locale.current.identifier.components(separatedBy: "_").first == "he")
    
    @State private var gameState: GameState = .inProgress { didSet { showPopup = gameState != .inProgress } }
    @State private var showPopup: Bool = false
    
    @State private var wordNumber = 0
    
    private let hitPoints = 20
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }

    @State private var turn: Turn {
        didSet {
            guard turn == .ai else { return }
            let aiWord = {
                func bestGuess() -> (text: String, colors: [LetterFeedback]) {
                    var text = ""
                    var newColors = [LetterFeedback]()
                    
                    let ai = current > 0 ? aiColors[current - 1] : [.noGuess, .noGuess, .noGuess, .noGuess, .noGuess]
                    let player = colors[current]
                    
                    for i in 0..<colors[current].count {
                        if ai[i] < player[i] {
                            text += matrix[current][i]
                            newColors.append(player[i].getColor())
                        } else {
                            text += current > 0 ? aiMatrix[current - 1][i] : generateWord(length: 1)
                            newColors.append(current > 0 ? ai[i].getColor() : .gray)
                        }
                    }
                    
                    return (text, newColors)
                }
                
                let bestGuess = bestGuess()
                return ai.submitFeedback(prv: (bestGuess.text, bestGuess.colors)).capitalizedFirst
            }().toArray()
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                var arr = [String](repeating: "", count: aiWord.count)
                for i in 0..<aiWord.count {
                    arr[i] = aiWord[i]
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    aiMatrix[current] = arr
                }
            }
        }
    }
    
    init() {
        self.matrix = [[String]](repeating: [String](repeating: "",
                                                     count: DifficultyType.roguelike.getLength()),
                                 count: rows)
        self.colors = [[CharColor]](repeating: [CharColor](repeating: .noGuess,
                                                           count: DifficultyType.roguelike.getLength()),
                                    count: rows)
        
        self.aiMatrix = [[String]](repeating: [String](repeating: "",
                                                     count: DifficultyType.roguelike.getLength()),
                                 count: rows)
        self.aiColors = [[CharColor]](repeating: [CharColor](repeating: .noGuess,
                                                           count: DifficultyType.roguelike.getLength()),
                                    count: rows)
        self.current = 0
        
        self.turn = .player
    }
    
    var body: some View {
        conatnet()
    }
    
    @ViewBuilder private func conatnet() -> some View {
        GeometryReader { proxy in
            background(proxy: proxy)
            ZStack(alignment: .top) {
                AdView(adUnitID: "GameBanner")
                game(proxy: proxy)
                    .padding(.top, 48)
                overlayViews(proxy: proxy)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: interstitialAdManager.interstitialAdLoaded) {
            guard interstitialAdManager.interstitialAdLoaded else { return }
            interstitialAdManager.displayInterstitialAd { initalConfigirationForWord() }
        }
        .onChange(of: playerHP) {
            if playerHP == 0 {
                gameState = .lose
            }
        }
        .onChange(of: aiHP) {
            if aiHP == 0 {
                gameState = .win
            }
        }
        .customAlert("YOU vs AI",
                     type: gameState == .win ? .success : .fail,
                     isPresented: $showPopup,
                     actionText: "OK",
                     action: {
            audio.stop()
            router.navigateBack()
        }, message: {
            Text("You \(gameState == .win ? "win".localized : "lose".localized)")
        })
    }
    
    @ViewBuilder private func background(proxy: GeometryProxy) -> some View {
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
        if !vm.isError && vm.word != .emapty && timeAttackAnimationDone {
            VStack(spacing: 8) {
                ZStack(alignment: .bottom) {
                    ZStack(alignment: .top) {
                        ZStack(alignment: .trailing) {
                            HStack {
                                Spacer()
                                
                                VStack {
                                    Image("player")
                                        .resizable()
                                        .frame(width: 60, height: 60)
                                        .opacity(turn == .player ? 1 : 0.3)
                                    
                                    ZStack {
                                        Text("HP: \(playerHP)")
                                        
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
                                }
                                
                                Spacer()
                                
                                VStack {
                                    Image("ai")
                                        .resizable()
                                        .frame(width: 60, height: 60)
                                        .opacity(turn == .ai ? 1 : 0.3)
                                    
                                    ZStack {
                                        Text("HP: \(aiHP)")
                                        
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
                                }
                                
                                Spacer()
                            }
                        }
                        .padding(.vertical)
                    }
                    .shadow(radius: 4)
                }
                
                ForEach(0..<rows, id: \.self) { i in
                    ZStack {
                        switch turn {
                        case .player:
                            WordView(length: length,
                                     word: $matrix[i],
                                     gainFocus: .constant(true),
                                     colors: $colors[i]) {
                                guard i == current else { return }
                                colors[i] = calcGuess(word: matrix[i])
                                if chackWord(i: i, matrix: matrix) {
                                    makeHitOnAI()
                                }
                                
                                if current == rows - 1 {
                                    withAnimation(.easeInOut(duration: 0.6).delay(0.5)) {
                                        turn = .ai
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
                                     word: $aiMatrix[i],
                                     gainFocus: .constant(true),
                                     colors: $aiColors[i]) {
                                guard i == current else { return }
                                aiColors[i] = calcGuess(word: aiMatrix[i])
                                if chackWord(i: i, matrix: aiMatrix) {
                                    makeHitOnPlayer()
                                }
                                
                                if current < rows - 1 {
                                    current = i + 1
                                } else if current == rows - 1 {
                                    Task {
                                        await vm.wordForAiMode(email: loginHandeler.model!.email)
                                    }
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
                
                AppTitle()
                    .padding(.top, 90)
                    .padding(.bottom, 140)
                    .shadow(radius: 4)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)
        }
    }
    
    @ViewBuilder private func game(proxy: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) { gameBody(proxy: proxy) }
                .ignoresSafeArea(.keyboard)
                .onAppear { Task { await vm.wordForAiMode(email: loginHandeler.model!.email) } }
                .onChange(of: vm.isError) {
                    guard vm.isError else { return }
                    keyboard.show = true
                }
                .onChange(of: vm.word.word) {
                    initMatrixState()
                    wordNumber += 1
                    guard wordNumber % InterstitialAdInterval != 0 else { return interstitialAdManager.loadInterstitialAd() }
                    initalConfigirationForWord()
                }
                .ignoresSafeArea(.keyboard)
            
            HStack {
                backButton()
                Spacer()
            }
        }
    }
    
    private func initalConfigirationForWord() {
        queue.asyncAfter(deadline: .now() + (keyboard.show ? 0 : 0.5)) {
            audio.playSound(sound: "backround",
                            type: "mp3",
                            loop: true)
        }
        return current = 0
    }
    
    @ViewBuilder private func overlayViews(proxy: GeometryProxy) -> some View {
        if !vm.isError && !endFetchAnimation && !keyboard.show { fetchingView() }
        else if vm.word.isTimeAttack { timeAttackView(proxy: proxy) }
    }
    
    @ViewBuilder private func fetchingView() -> some View {
        VStack {
            Spacer()
            if vm.word == .emapty {
                TextAnimation(text: "Fetching Word".localized)
                    .padding(.bottom, 24)
            }
            AppTitle()
            Spacer()
        }
        .offset(y: vm.word == .emapty ? -80 : 340)
        .shadow(radius: 4)
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
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            Text("double points")
                .font(.title)
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .scaleEffect(.init(1.2))
        .background(Color.white.ignoresSafeArea())
        .opacity(timeAttackAnimation ? 1 : 0)
        .offset(x: timeAttackAnimation ? 0 : proxy.size.width)
    }
    
    @ViewBuilder func backButton() -> some View {
        Button {
            audio.stop()
            router.navigateBack()
        } label: {
            Image(systemName: "\(language == "he" ? "forward" : "backward").end.fill")
                .resizable()
                .foregroundStyle(Color.black)
                .frame(height: 40)
                .frame(width: 40)
                .padding(.leading, 10)
                .padding(.top, 10)
        }
    }
    
    private func chackWord(i: Int, matrix: [[String]]) -> Bool {
        let guess = matrix[i].joined()
        
        if guess.lowercased() == vm.word.word.value.lowercased() || i == rows - 1 {
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
            withAnimation(.easeInOut(duration: 0.6).delay(turn == .ai ? 1.5 : 0.5)) {
                turn = .init(rawValue: 1 - turn.rawValue)!
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
        
        queue.asyncAfter(deadline: .now() + 1) {
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
        withAnimation(.linear(duration: 0.6)) {
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
    }
    
    private func calcGuess(word: [String]) -> [CharColor] {
        var colors = [CharColor](repeating: .noMatch,
                                 count: length)
        var containd = [String: Int]()
        
        for char in vm.word.word.value.lowercased() {
            let key = String(char).returnChar(isFinal: false)
            if containd[key] == nil {
                containd[key] = 1
            }
            else {
                containd[key]! += 1
            }
        }
        
        for i in 0..<word.count {
            if word[i].lowercased().isEquel(vm.word.word.value[i].lowercased()) {
                containd[word[i].lowercased().returnChar(isFinal: false)]! -= 1
                colors[i] = .extectMatch
            }
        }
        
        for i in 0..<word.count {
            guard !word[i].lowercased().isEquel(vm.word.word.value[i].lowercased()) else { continue }
            if vm.word.word.value.lowercased().toSuffixChars().contains(word[i].lowercased().returnChar(isFinal: true)) && containd[word[i].lowercased().returnChar(isFinal: false)]! > 0 {
                containd[word[i].lowercased().returnChar(isFinal: false)]! -= 1
                colors[i] = .partialMatch
            }
            else {
                colors[i] = .noMatch
            }
        }
        
        return colors
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).capitalized + dropFirst()
    }
}

//#Preview {
//    AIGameView()
//        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
//}
