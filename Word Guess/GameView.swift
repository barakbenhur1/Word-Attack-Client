//
//  ContentView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI
import CoreData
import Combine

enum FieldFocus: Int {
    case one
    case two
    case trhee
    case four
    case five
    case six
}

struct GameView<VM: ViewModel>: View {
    @EnvironmentObject private var coreData: PersistenceController
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    
    private let queue = DispatchQueue.main
    private let InterstitialAdInterval: Int = 7
    private let rows: Int = 5
    private let diffculty: DifficultyType
    private var length: Int { return diffculty.getLength() }
    private var email: String? { return loginHandeler.model?.email }
    
    @State private var current: Int = 0 { didSet { vm.current = current } }
    @State private var score: Int = 0
    @State private var scoreAnimation: (value: Int, opticity: CGFloat, scale: CGFloat, offset: CGFloat) = (0, CGFloat(0), CGFloat(0), CGFloat(30))
    @State private var matrix: [[String]]
    @State private var colors: [[CharColor]]
    @State private var vm = VM()
    @State private var keyboard = KeyboardHeightHelper()
    @State private var timeAttackAnimation = false
    @State private var timeAttackAnimationDone = true
    @State private var endFetchAnimation = false
    @State private var interstitialAdManager = InterstitialAdsManager(adUnitID: "GmaeInterstitial")
    
    private var language: String? { return local.locale.identifier.components(separatedBy: "_").first }
    
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
                        if diffculty == .tutorial {
                            VStack {
                                Text("Tutorial")
                                    .font(.largeTitle)
                                
                                let attr: AttributedString = {
                                    if current < 3 || current == .max {
                                        return AttributedString("Guess The 4 Letters Word".localized())
                                    }
                                    else {
                                        let theWord = vm.word.word.value
                                        var attr = AttributedString("\("the word is".localized()) \"\(theWord)\" \("try it, or not ;)".localized())")
                                        let range = attr.range(of: theWord)!
                                        attr.foregroundColor = .black.opacity(0.5)
                                        attr[range].foregroundColor = .orange
                                        return attr
                                    }
                                }()
                                
                                Text(attr)
                                    .font(.callout.weight(.heavy))
                                    .shadow(radius: 4)
                            }
                            .padding()
                        }
                        else {
                            ZStack(alignment: .trailing) {
                                HStack {
                                    Spacer()
                                    VStack {
                                        Text("Score")
                                            .multilineTextAlignment(.center)
                                            .font(.title3.weight(.heavy))
                                            .shadow(radius: 4)
                                            .foregroundStyle(.black)
                                        
                                        ZStack(alignment: .top) {
                                            Text("\(vm.word.score)")
                                                .multilineTextAlignment(.center)
                                                .font(.largeTitle.weight(.heavy))
                                                .foregroundStyle(.angularGradient(colors: [.red,
                                                                                           .yellow,
                                                                                           .green],
                                                                                  center: .center,
                                                                                  startAngle: .zero,
                                                                                  endAngle: .degrees(360)))
                                                .shadow(radius: 4)
                                            
                                            let value = vm.word.isTimeAttack ? scoreAnimation.value / 2 : scoreAnimation.value
                                            let color: Color = value == 0 ? .red : value < 80 ? .yellow : .green
                                            
                                            Text("+ \(scoreAnimation.value)")
                                                .font(.largeTitle.weight(.heavy))
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
                                        }
                                    }
                                    .padding(.top, -10)
                                    .fixedSize(horizontal: false,
                                               vertical: true)
                                    Spacer()
                                }
                                
                                HStack {
                                    Spacer()
                                    VStack {
                                        Text("\(diffculty.rawValue.localized())")
                                            .multilineTextAlignment(.center)
                                            .font(.title3.weight(.heavy))
                                            .shadow(radius: 4)
                                            .padding(.bottom, 2)
                                        Text("words: \(vm.word.number)")
                                            .multilineTextAlignment(.center)
                                            .font(.title3.weight(.heavy))
                                            .shadow(radius: 4)
                                            .padding(.bottom, 8)
                                    }
                                    .padding(.top, -10)
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                    .shadow(radius: 4)
                }
                .padding(.bottom, -15)
                
                ForEach(0..<rows, id: \.self) { i in
                    ZStack {
                        WordView(length: length,
                                 word: $matrix[i],
                                 gainFocus: .constant(true),
                                 colors: $colors[i]) {
                            guard i == current else { return }
                            nextLine(i: i)
                        }
                                 .disabled(current != i)
                                 .environmentObject(vm)
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
                .onAppear { Task { await vm.word(diffculty: diffculty,
                                                 email: loginHandeler.model!.email) } }
                .onChange(of: vm.isError) {
                    guard vm.isError else { return }
                    keyboard.show = true
                }
                .onChange(of: vm.word.word) {
                    initMatrixState()
                    guard !keyboard.show || vm.word.number == 0 || vm.word.number % InterstitialAdInterval != 0 else { return interstitialAdManager.loadInterstitialAd() }
                    initalConfigirationForWord()
                }
                .onChange(of: vm.word.word.guesswork) {
                    let guesswork = vm.word.word.guesswork
                    for i in 0..<guesswork.count {
                        for j in 0..<guesswork[i].count {
                            matrix[i][j] = guesswork[i][j]
                        }
                        colors[i] = calcGuess(word: matrix[i])
                    }
                    
                    guard !keyboard.show || vm.word.number == 0 || vm.word.number % InterstitialAdInterval != 0 else { return }
                    guard vm.word.isTimeAttack else { return }
                    current = guesswork.count
                }
                .onChange(of: vm.word.isTimeAttack) {
                    guard !keyboard.show || vm.word.number == 0 || vm.word.number % InterstitialAdInterval != 0 else { return }
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
        guard vm.word.isTimeAttack else {
            queue.asyncAfter(deadline: .now() + (keyboard.show ? 0 : 0.5)) {
                guard diffculty != .tutorial else { return }
                audio.playSound(sound: "backround",
                                type: "mp3",
                                loop: true)
            }
            return current = vm.word.word.guesswork.count
        }
        timeAttackAnimationDone = false
        queue.asyncAfter(deadline: .now() + (keyboard.show ? 0 : 0.5)) {
            endFetchAnimation = true
            withAnimation(.interpolatingSpring(.smooth)) { timeAttackAnimation = true }
            queue.asyncAfter(deadline: .now() + 1) {
                timeAttackAnimationDone = true
                timeAttackAnimation = false
                queue.asyncAfter(deadline: .now() + 0.3) {
                    current = vm.word.word.guesswork.count
                    audio.playSound(sound: "tick",
                                    type: "wav",
                                    loop: true)
                }
            }
        }
    }
    
    @ViewBuilder private func overlayViews(proxy: GeometryProxy) -> some View {
        if !vm.isError && !endFetchAnimation && !keyboard.show && diffculty != .tutorial { fetchingView() }
        else if vm.word.isTimeAttack { timeAttackView(proxy: proxy) }
    }
    
    @ViewBuilder private func fetchingView() -> some View {
        VStack {
            Spacer()
            if vm.word == .emapty {
                TextAnimation(text: "Fetching Word".localized())
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
            if diffculty == .tutorial {
                hideKeyboard()
                coreData.new()
            }
            router.navigateBack()
        } label: {
            if diffculty == .tutorial {
                Text("skip")
                    .font(.title)
                    .foregroundStyle(.black)
                    .padding(.leading, 10)
                    .padding(.top, 10)
            }
            else {
                Image(systemName: "\(language == "he" ? "forward" : "backward").end.fill")
                    .resizable()
                    .foregroundStyle(Color.black)
                    .frame(height: 40)
                    .frame(width: 40)
                    .padding(.leading, 10)
                    .padding(.top, 10)
            }
        }
    }
    
    private func nextLine(i: Int)  {
        colors[i] = calcGuess(word: matrix[i])
        
        let guess = matrix[i].joined()
        
        if guess.lowercased() == vm.word.word.value.lowercased() || i == rows - 1 {
            current = .max
            guard let email else { return }
            
            audio.stop()
            
            let correct = guess.lowercased() == vm.word.word.value.lowercased()
            
            guard diffculty != .tutorial else {
                return queue.asyncAfter(wallDeadline: .now() + 0.2) {
                    let sound = correct ? "success" : "fail"
                    audio.playSound(sound: sound,
                                    type: "wav")
                    
                    return queue.asyncAfter(wallDeadline: .now() + 1) {
                        coreData.new()
                        router.navigateBack()
                    }
                }
            }
            
            if correct {
                let points = vm.word.isTimeAttack ? 40 : 20
                score(value: rows * points - i * points)
            }
            else { score(value: 0) }
            
            Task {
                if !correct { await vm.addGuess(diffculty: diffculty, email: email, guess: guess) }
                await vm.score(diffculty: diffculty, email: email)
                await vm.word(diffculty: diffculty, email: email)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.5)) {
                        scoreAnimation.opticity = 0
                        scoreAnimation.scale = 0
                    }
                    queue.asyncAfter(wallDeadline: .now() + 0.5) {
                        Task {
                            await MainActor.run {
                                scoreAnimation.value = 0
                                scoreAnimation.offset = 30
                            }
                        }
                    }
                }
            }
        }
        else if i == current && i + 1 > vm.word.word.guesswork.count {
            guard let email else { return }
            current = i + 1
            guard diffculty != .tutorial else { return }
            Task { await vm.addGuess(diffculty: diffculty, email: email, guess: guess) }
        }
    }
    
    private func initMatrixState() {
        matrix = [[String]](repeating: [String](repeating: "",
                                                count: length),
                            count: rows)
        colors = [[CharColor]](repeating: [CharColor](repeating: .noGuess,
                                                      count: length),
                               count: rows)
    }
    
    private func score(value: Int) {
        scoreAnimation.value = value
        withAnimation(.linear(duration: 1.4)) {
            scoreAnimation.offset = 0
            scoreAnimation.opticity = 1
            scoreAnimation.scale = 0.9
        }
        
        queue.asyncAfter(deadline: .now() + 1.6) {
            let sound = value > 0 ? "success" : "fail"
            audio.playSound(sound: sound,
                            type: "wav")
            guard scoreAnimation.opticity == 1 else { return }
            withAnimation(.linear(duration: 0.2)) {
                scoreAnimation.opticity = 0
                scoreAnimation.scale = 0
                vm.word.score += value
                vm.word.number += 1
            }
            
            queue.asyncAfter(deadline: .now() + 0.2) {
                scoreAnimation.value = 0
                scoreAnimation.offset = 30
            }
        }
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

//#Preview {
//    GameView(diffculty: .regular)
//        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
//}

extension String {
    subscript(offset: Int) -> String { String(self[index(startIndex, offsetBy: offset)]) }
    subscript(range: Range<Int>) -> SubSequence {
        let startIndex = index(self.startIndex, offsetBy: range.lowerBound)
        return self[startIndex..<index(startIndex, offsetBy: range.count)]
    }
    subscript(range: ClosedRange<Int>) -> SubSequence {
        let startIndex = index(self.startIndex, offsetBy: range.lowerBound)
        return self[startIndex..<index(startIndex, offsetBy: range.count)]
    }
    subscript(range: PartialRangeFrom<Int>) -> SubSequence { self[index(startIndex, offsetBy: range.lowerBound)...] }
    subscript(range: PartialRangeThrough<Int>) -> SubSequence { self[...index(startIndex, offsetBy: range.upperBound)] }
    subscript(range: PartialRangeUpTo<Int>) -> SubSequence { self[..<index(startIndex, offsetBy: range.upperBound)] }
    
    func localized() -> String {
        return NSLocalizedString(self, comment: "")
    }
}

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
                // disable the default FullScreenCover animation
                transaction.disablesAnimations = true
                
                // add custom animation for presenting and dismissing the FullScreenCover
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
        .onReceive(timer) { input in
            value += every
            current = Int(value / total * CGFloat(length))
            trigger += 1
            
            if value >= total {
                timer
                    .upstream
                    .connect()
                    .cancel()
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
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
