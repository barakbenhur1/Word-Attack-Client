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

struct GameView<VM: WordViewModel>: View {
    @EnvironmentObject private var coreData: PersistenceController
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var premium: PremiumManager
    @EnvironmentObject private var adProvider: AdProvider
    
    private let queue = DispatchQueue.main
    private let InterstitialAdInterval: Int = 7
    private let rows: Int = 5
    private let diffculty: DifficultyType
    private var length: Int { return diffculty.getLength() }
    private var email: String? { return loginHandeler.model?.email }
    private var interstitialAdManager: InterstitialAdsManager? { adProvider.interstitialAdsManager(id: "GameInterstitial") }
    
    @State private var current: Int = 0
    @State private var score: Int = 0
    @State private var scoreAnimation: (value: Int, opticity: CGFloat, scale: CGFloat, offset: CGFloat) = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var vm = VM()
    @State private var keyboard = KeyboardHeightHelper()
    @State private var timeAttackAnimation = false
    @State private var timeAttackAnimationDone = true
    @State private var endFetchAnimation = false
    @State private var showError: Bool = false
    
    @State private var cleanCells = false
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
    private func handleError() {
        guard vm.isError else { return }
        showError = true
    }
    
    private func closeAfterError() {
        keyboard.show = true
        audio.stop()
        router.navigateBack()
    }
    
    private func handleWordChange() {
        initMatrixState()
        guard interstitialAdManager == nil || !keyboard.show || vm.word.number == 0 || vm.word.number % InterstitialAdInterval != 0 else { interstitialAdManager?.loadInterstitialAd(); return }
        initalConfigirationForWord()
        guard diffculty != .tutorial && diffculty != .ai else { return }
        Task(priority: .utility) { await SharedStore.writeDifficultyStatsAsync(.init(answers: vm.word.number, score: vm.score), for: diffculty.liveValue) }
    }
    
    private func handleTimeAttackIfNeeded() {
        guard diffculty != .tutorial else { return }
        guard endFetchAnimation && vm.word.isTimeAttack else { return }
        timeAttackAnimationDone = false
        withAnimation(.interpolatingSpring(.smooth)) { timeAttackAnimation = true }
        queue.asyncAfter(deadline: .now() + 2) {
            timeAttackAnimationDone = true
            timeAttackAnimation = false
            queue.asyncAfter(deadline: .now() + 0.3) {
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
        
        guard !keyboard.show || vm.word.number == 0 || vm.word.number % InterstitialAdInterval != 0 else { return }
        guard vm.word.isTimeAttack else { return }
        current = guesswork.count
    }
    
    private func onAppear(email: String) {
        if diffculty == .tutorial {
            coreData.new()
            Task(priority: .userInitiated) {
                await handleNewWord(email: email)
            }
        } else {
            Task.detached(priority: .userInitiated) {
                await handleNewWord(email: email)
            }
        }
    }
    
    private func handleNewWord(email: String) async {
        await vm.getScore(diffculty: diffculty, email: email)
        await vm.word(diffculty: diffculty, email: email)
    }
    
    private func afterTimeAttack() {
        guard !vm.word.isTimeAttack else { return }
        guard !keyboard.show || vm.word.number == 0 || vm.word.number % InterstitialAdInterval != 0 else { return }
        initalConfigirationForWord()
    }
    
    init(diffculty: DifficultyType) {
        self.diffculty = diffculty
        
        self.matrix = [[String]](repeating: [String](repeating: "",
                                                     count: diffculty.getLength()),
                                 count: rows)
        self.colors = [[CharColor]](repeating: [CharColor](repeating: .noGuess,
                                                           count: diffculty.getLength()),
                                    count: rows)
        self.current = 0
    }
    
    var body: some View {
        conatnet()
            .ignoresSafeArea(.keyboard)
            .onChange(of: interstitialAdManager?.interstitialAdLoaded) {
                guard interstitialAdManager?.interstitialAdLoaded ?? false else { initalConfigirationForWord(); return }
                interstitialAdManager?.displayInterstitialAd { initalConfigirationForWord() }
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
    
    @ViewBuilder private func gameBody() -> some View {
        if !vm.isError && vm.word != .empty {
            VStack(spacing: 8) {
                ZStack(alignment: .bottom) {
                    ZStack(alignment: .top) {
                        if diffculty == .tutorial {
                            VStack {
                                // Title
                                Text("Tutorial")
                                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                    .themedText(.primary)
                                    .softTextShadow()
                                
                                // Subtitle / hint
                                let attr: AttributedString = {
                                    if current < 3 || current == .max {
                                        var a = AttributedString("Guess The 4 Letters Word".localized)
                                        a.foregroundColor = .white.opacity(0.85)
                                        return a
                                    } else {
                                        let theWord = vm.word.word.value
                                        var a = AttributedString("\("the word is".localized) \"\(theWord)\" \("try it, or not ;)".localized)")
                                        let range = a.range(of: theWord)!
                                        a.foregroundColor = .white.opacity(0.8)
                                        a[range].foregroundColor = .orange
                                        return a
                                    }
                                }()
                                
                                Text(attr)
                                    .font(.system(.callout, design: .rounded).weight(.semibold))
                                    .softTextShadow()
                            }
                            .padding()
                        } else {
                            ZStack(alignment: .trailing) {
                                HStack {
                                    // Left: Difficulty
                                    VStack {
                                        Spacer()
                                        Text(diffculty.stringValue)
                                            .multilineTextAlignment(.center)
                                            .font(.system(.title3, design: .rounded).weight(.semibold))
                                            .themedText(.primary)
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
                                            .themedText(.secondary)
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
                                    
                                    // Right: Words count
                                    VStack {
                                        Spacer()
                                        Text("words: \(vm.word.number)")
                                            .multilineTextAlignment(.center)
                                            .font(.system(.title3, design: .rounded).weight(.semibold))
                                            .monospacedDigit()
                                            .themedText(.primary)
                                            .softTextShadow()
                                            .padding(.bottom, 8)
                                            .padding(.trailing, 10)
                                    }
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                    .shadow(radius: 4)
                }
                .padding(.bottom, -10)
                
                // Rows
                ForEach(0..<rows, id: \.self) { i in
                    ZStack {
                        let gainFocus = Binding(get: { current == i && endFetchAnimation && !timeAttackAnimation && timeAttackAnimationDone },
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
                        
                        if keyboard.show && vm.word.isTimeAttack && timeAttackAnimationDone && current == i {
                            let start = Date()
                            let end = start.addingTimeInterval(diffculty == .easy ? 20 : 15)
                            ProgressBarView(length: length,
                                            value: 0,
                                            total: end.timeIntervalSinceNow - start.timeIntervalSinceNow,
                                            done: { nextLine(i: i) })
                            .opacity(0.2)
                        }
                    }
                }
                
                if endFetchAnimation {
                    AppTitle(size: 50)
                        .padding(.top, UIDevice.isPad ? 130 : 90)
                        .padding(.bottom, UIDevice.isPad ? 190 : 140)
                        .shadow(radius: 4)
                } else {
                    ZStack{}
                        .frame(height: UIDevice.isPad ? 81 : 81)
                        .padding(.top, UIDevice.isPad ? 130 : 90)
                        .padding(.bottom, UIDevice.isPad ? 190 : 140)
                        .shadow(radius: 4)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)
        }
    }
    
    @ViewBuilder private func game() -> some View {
        if let email {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) { gameBody() }
                    .ignoresSafeArea(.keyboard)
                    .onChange(of: vm.isError, handleError)
                    .onChange(of: vm.word.word, handleWordChange)
                    .onChange(of: vm.word.word.guesswork, handleGuessworkChage)
                    .onChange(of: vm.word.isTimeAttack, afterTimeAttack)
                    .onChange(of: endFetchAnimation, handleTimeAttackIfNeeded)
                    .onAppear { onAppear(email: email) }
                    .disabled(!endFetchAnimation)
                    .opacity(endFetchAnimation ? 1 : 0.7)
                    .grayscale(endFetchAnimation ? 0 : 1)
            }
            .padding(.top, 44)
        }
    }
    
    private func initalConfigirationForWord() {
        guard diffculty != .tutorial else { return }
        Task(priority: .high) {
            try? await Task.sleep(nanoseconds: (keyboard.show ? 0 : 500_000_000))
            audio.playSound(sound: "backround",
                            type: "mp3",
                            loop: true)
            
            //            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { endFetchAnimation = true }
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
                .themedText(.primary)
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
        audio.stop()
        if diffculty == .tutorial {
            UIApplication.shared.hideKeyboard()
        }
        router.navigateBack()
    }
    
    private func nextLine(i: Int)  {
        colors[i] = vm.calculateColors(with: matrix[i])
        
        let guess = matrix[i].joined()
        
        if guess.lowercased() == vm.word.word.value.lowercased() || i == rows - 1 {
            current = .max
            audio.stop()
            
            let correct = guess.lowercased() == vm.word.word.value.lowercased()
            
            guard diffculty != .tutorial else {
                Task(priority: .userInitiated) {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    let sound = correct ? "success" : "fail"
                    audio.playSound(sound: sound,
                                    type: "wav")
                    
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    router.navigateBack()
                }
                
                return
            }
            
            if correct {
                let points = vm.word.isTimeAttack ? 40 : 20
                score(value: rows * points - i * points)
            } else { score(value: 0) }
            
            //            Task.detached(priority: .userInitiated) {
            //                try? await Task.sleep(nanoseconds: 1_000_000_000)
            //                await MainActor.run { cleanCells = true }
            //            }
            
            queue.asyncAfter(deadline: .now() + 0.8) {
                let sound = correct ? "success" : "fail"
                audio.playSound(sound: sound,
                                type: "wav")
            }
            
            guard let email else { return }
            Task.detached(priority: .userInitiated) {
                if !correct { await vm.addGuess(diffculty: diffculty, email: email, guess: guess) }
                await vm.score(diffculty: diffculty, email: email)
                try? await Task.sleep(nanoseconds: 500_000_000)
                await handleNewWord(email: email)
            }
        } else if i == current && i + 1 > vm.word.word.guesswork.count {
            guard let email else { return }
            current = i + 1
            guard diffculty != .tutorial else { return }
            Task(priority: .userInitiated) { await vm.addGuess(diffculty: diffculty, email: email, guess: guess) }
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
    
    private func score(value: Int) {
        scoreAnimation.value = value
        withAnimation(.linear(duration: 1.4)) {
            scoreAnimation.offset = 0
            scoreAnimation.opticity = 1
            scoreAnimation.scale = 0.9
        }
        
        queue.asyncAfter(deadline: .now() + 1.44) {
            guard scoreAnimation.opticity == 1 else { return }
            withAnimation(.linear(duration: 0.2)) {
                scoreAnimation.opticity = 0
                scoreAnimation.scale = 0
            }
            
            queue.asyncAfter(deadline: .now() + 0.2) {
                vm.score += value
                vm.word.number += 1
                scoreAnimation.value = 0
                scoreAnimation.offset = 30
            }
            
//            await MainActor.run {
//                withAnimation(.easeOut(duration: 0.5)) {
//                    scoreAnimation.opticity = 0
//                    scoreAnimation.scale = 0
//                }
//                queue.asyncAfter(wallDeadline: .now() + 0.5) {
//                    Task.detached {
//                        await MainActor.run {
//                            scoreAnimation.value = 0
//                            scoreAnimation.offset = 30
//                        }
//                    }
//                }
//            }
        }
    }
}

//#Preview {
//    GameView(diffculty: .regular)
//        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
//}

extension View {
    /// Presents an alert with a message when a given condition is true, using a localized string key for a title.
    /// - Parameters:
    ///   - titleKey: The key for the localized string that describes the title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to present the alert.
    ///   - data: An optional binding of generic type T value, this data will populate the fields of an alert that will be displayed to the user.
    ///   - actionText: The key for the localized string that describes the text of alert's action button.
    ///   - action: The alert’s action given the currently available data.
    ///   - message: A ViewBuilder returning the message for the alert given the currently available data.
    func customAlert<M, T: Any>(
        _ titleKey: LocalizedStringKey,
        type: AlertType,
        isPresented: Binding<Bool>,
        returnedValue data: T?,
        actionText: LocalizedStringKey,
        cancelButtonText: LocalizedStringKey? = nil,
        action: @escaping (T) -> (),
        @ViewBuilder message: @escaping (T?) -> M
    ) -> some View where M: View {
        fullScreenCover(isPresented: isPresented) {
            CustomAlertView(
                type: type,
                titleKey,
                isPresented,
                returnedValue: data,
                actionTextKey: actionText,
                cancelButtonTextKey: cancelButtonText,
                action: action,
                message: message
            )
            .presentationBackground(.clear)
        }
        .transaction { transaction in
            if isPresented.wrappedValue {
                // disable the default FullScreenCover animation
                transaction.disablesAnimations = true
                // add custom animation for presenting and dismissing the FullScreenCover
                transaction.animation = .linear(duration: 0.1)
            }
        }
    }
    
    /// Presents an alert with a message when a given condition is true, using a localized string key for a title.
    /// - Parameters:
    ///   - titleKey: The key for the localized string that describes the title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to present the alert.
    ///   - actionText: The key for the localized string that describes the text of alert's action button.
    ///   - action: Returning the alert’s actions.
    ///   - message: A ViewBuilder returning the message for the alert.
    func customAlert<M>(
        _ titleKey: LocalizedStringKey,
        type: AlertType,
        isPresented: Binding<Bool>,
        actionText: LocalizedStringKey,
        cancelButtonText: LocalizedStringKey? = nil,
        action: (() -> ())? = nil,
        @ViewBuilder message: @escaping () -> M
    ) -> some View where M: View {
        fullScreenCover(isPresented: isPresented) {
            CustomAlertView(
                type: type,
                titleKey,
                isPresented,
                actionTextKey: actionText,
                cancelButtonTextKey: cancelButtonText,
                action: action,
                message: message
            )
            .presentationBackground(.clear)
        }
        .transaction { transaction in
            if isPresented.wrappedValue {
                transaction.disablesAnimations = true
                transaction.animation = .linear(duration: 0.1)
            }
        }
    }
}

@Observable
class KeyboardHeightHelper: ObservableObject {
    var keyboardHeight: CGFloat = 0
    var show: Bool = false
    
    init() { listenForKeyboardNotifications() }
    
    deinit { NotificationCenter.default.removeObserver(self) }
    
    private func listenForKeyboardNotifications() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification,
                                               object: nil,
                                               queue: .main) { notification in
            guard let userInfo = notification.userInfo,
                  let keyboardRect = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            
            self.keyboardHeight = keyboardRect.height
            self.show = true
        }
        
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification,
                                               object: nil,
                                               queue: .main) { (notification) in
            //            self.keyboardHeight = 0
        }
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
            value += every
            current = Int(value / total * CGFloat(length))
            trigger += 1
            
            if value >= total {
                timer.upstream.connect().cancel()
                done()
            }
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
