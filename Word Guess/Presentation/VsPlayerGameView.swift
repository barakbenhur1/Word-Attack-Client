//
//  VsPlayerGameView.swift
//  WordZap
//
//  PVP version: local player is always P1 (interactive),
//  remote opponent is always P2 (display-only).
//

import SwiftUI
import CoreData
import Combine

fileprivate enum PvPResult {
    case none, player1Win, player2Win, draw
}

struct VsPlayerGameView<VM: VsPlayerGameViewModel>: View {
    // MARK: - Environment
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var coreData: PersistenceController
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @EnvironmentObject private var screenManager: ScreenManager
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var local: LanguageSetting
    @EnvironmentObject private var premium: PremiumManager
    //    @EnvironmentObject private var session: GameSessionManager
    
    // MARK: - Game configuration
    private let rows: Int = 5
    private var length: Int { DifficultyType.pvp.getLength() }
    
    private var uniqe: String? { loginHandeler.model?.uniqe }
    
    /// Match id passed from the PVP queue / lobby (optional).
    private let initialMatchId: String?
    
    // MARK: - State (VM + game)
    @State private var vm = VM()
    
    @State private var endFetchAnimation: Bool
    @State private var didStart: Bool
    
    @State private var gender: String?
    @State private var opponentGender: String?
    
    @State private var currentRow: Int
    
    // Player 1 board (local, editable)
    @State private var p1Matrix: [[String]]
    @State private var p1Colors: [[CharColor]]
    
    // Player 2 board (opponent, display-only)
    @State private var p2Matrix: [[String]]
    @State private var p2Colors: [[CharColor]]
    
    // Flow flags
    @State private var cleanCells: Bool
    @State private var disabled: Bool       // locks input when true
    @State private var isVisible: Bool
    
    // Turn + coin flip
    @State private var turn: PvPTurn
    @State private var showCoinFlip: Bool
    
    // Coin flip result from server
    @State private var coinFlipWinner: PvPTurn?
    @State private var coinFlipRequestInFlight: Bool
    
    // Short-lived "Your Turn / Opponent Turn" banner
    @State private var showTurnOverlay: Bool
    @State private var turnOverlayTask: Task<Void, Never>?
    
    // Game-over
    @State private var result: PvPResult
    @State private var showGameEndPopup: Bool
    @State private var showExitPopup: Bool
    @State private var showError: Bool
    @State private var showOpponentLeftPopup: Bool
    
    // Queue / matching overlay
    @State private var isMatching: Bool = false
    
    // Tasks
    @State private var delayedNavTask: Task<Void, Never>?
    
    private var language: String? {
        local.locale.identifier.components(separatedBy: "_").first
    }
    
    private var allBestGuesses: [BestGuess] { return vm.perIndexCandidatesSparse(matrix: p1Matrix,
                                                                                 colors: p1Colors,
                                                                                 matrix2: p2Matrix,
                                                                                 colors2: p1Colors) }
    
    // MARK: - Init
    
    /// `matchId` should be the same for both players (from the PVP queue / lobby).
    init(matchId: String? = nil) {
        self.initialMatchId = matchId
        
        let L = DifficultyType.pvp.getLength()
        let R = 5
        let emptyRow = [String](repeating: "", count: L)
        let emptyColors = [CharColor](repeating: .noGuess, count: L)
        
        _p1Matrix = State(initialValue: [[String]](repeating: emptyRow, count: R))
        _p1Colors = State(initialValue: [[CharColor]](repeating: emptyColors, count: R))
        _p2Matrix = State(initialValue: [[String]](repeating: emptyRow, count: R))
        _p2Colors = State(initialValue: [[CharColor]](repeating: emptyColors, count: R))
        
        _endFetchAnimation = State(initialValue: false)
        _didStart = State(initialValue: false)
        
        _cleanCells = State(initialValue: false)
        _disabled = State(initialValue: false)
        _isVisible = State(initialValue: false)
        
        _currentRow = State(initialValue: 0)
        
        _turn = State(initialValue: .player1)
        _showCoinFlip = State(initialValue: false)
        
        _coinFlipWinner = State(initialValue: nil)
        _coinFlipRequestInFlight = State(initialValue: false)
        
        _showTurnOverlay = State(initialValue: false)
        
        _result = State(initialValue: .none)
        _showGameEndPopup = State(initialValue: false)
        _showExitPopup = State(initialValue: false)
        _showError = State(initialValue: false)
        _showOpponentLeftPopup = State(initialValue: false)
    }
    
    // MARK: - Helpers
    
    private func resetBoard() {
        let emptyRow = [String](repeating: "", count: length)
        let emptyColors = [CharColor](repeating: .noGuess, count: length)
        
        p1Matrix = [[String]](repeating: emptyRow, count: rows)
        p1Colors = [[CharColor]](repeating: emptyColors, count: rows)
        
        p2Matrix = [[String]](repeating: emptyRow, count: rows)
        p2Colors = [[CharColor]](repeating: emptyColors, count: rows)
        
        currentRow = 0
        cleanCells = false
    }
    
    private func cancelAllTasks() {
        delayedNavTask?.cancel(); delayedNavTask = nil
        turnOverlayTask?.cancel(); turnOverlayTask = nil
    }
    
    // MARK: - Typing helpers (live opponent preview)
    @MainActor
    private func startOpponentTypingListenerIfNeeded() {
        vm.observeOpponentTyping { rowIndex, guess in
            guard turn == .player2 else { return }
            guard rowIndex >= 0 && rowIndex < rows else { return }
            
            let chars = Array(guess)
            var row = [String](repeating: "", count: length)
            for i in 0..<min(length, chars.count) {
                row[i] = String(chars[i])
            }
            p2Matrix[rowIndex] = row
        }
    }
    
    /// Listen for server turn changes (row-based).
    /// This is the key loop: every `pvp:rowDone` on the server produces a `pvp:turn`
    /// broadcast, and we decide:
    ///  - did the opponent just finish a row? → color + check win/draw
    ///  - do we get a next row? → update `turn`, `currentRow`, `disabled`
    @MainActor
    private func startTurnListenerIfNeeded(for localPlayerId: String) {
        vm.observeTurnChanges(localPlayerId: localPlayerId) { isMyTurn, nextRow in
            guard result == .none else { return }
            
            // State *before* applying the new turn.
            let prevTurn = turn
            let prevRow  = currentRow
            
            // If we are *gaining* the turn, then the opponent must have just
            // finished a row on the previous state.
            if prevTurn == .player2 && isMyTurn && result == .none {
                handleOpponentRowComplete(row: prevRow)
            }
            
            // Opponent move may have ended the game.
            guard result == .none else { return }
            
            // If the server says there is no valid next row for us (e.g. 5),
            // that simply means no more turns. Lock input and stop.
            guard nextRow >= 0 && nextRow < rows else {
                disabled = true
                return
            }
            
            // Normal turn switch
            turnOverlayTask?.cancel()
            
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                withAnimation {
                    turn = isMyTurn ? .player1 : .player2
                }
            }
            currentRow = nextRow
            disabled = !isMyTurn                    // only active player can type
            showTurnBanner(for: turn)
        }
    }
    
    /// Send our current row as a typing update to the opponent.
    private func sendTypingUpdateIfNeeded(row: Int) {
        guard turn == .player1 else { return }      // only send when it's our turn
        guard row == currentRow else { return }
        guard endFetchAnimation, didStart, !disabled else { return }
        guard !showCoinFlip else { return }
        guard let uniqe else { return }
        guard vm.currentMatchId?.isEmpty == false else { return }
        
        let guess = p1Matrix[row].joined()
        vm.sendTypingUpdate(uniqe: uniqe, row: row, guess: guess)
    }
    
    // MARK: - Game flow
    
    @MainActor
    private func startGame(fetchNewWord: Bool) async {
        guard let uniqe else { return }
        
        cancelAllTasks()
        disabled = true
        endFetchAnimation = false
        result = .none
        showGameEndPopup = false
        showTurnOverlay = false
        
        // Reset coin-flip state
        coinFlipWinner = nil
        coinFlipRequestInFlight = false
        
        resetBoard()
        
        await vm.word(uniqe: uniqe, newWord: fetchNewWord)
        didStart = vm.word != .empty
        
        endFetchAnimation = true
        // Wait for coinflip to decide who actually starts:
        disabled = true
        showCoinFlip = true
        turn = .player1  // default; real value set after coinflip
    }
    
    @MainActor
    private func finishRound(as result: PvPResult) {
        self.result = result
        disabled = true
        showTurnOverlay = false
        showGameEndPopup = true
    }
    
    @MainActor
    private func animatedTurnSwitch(to next: PvPTurn) {
        turn = next
        showTurnBanner(for: next)
    }
    
    @MainActor
    private func showTurnBanner(for turn: PvPTurn) {
        guard result == .none, !showCoinFlip else { return }
        turnOverlayTask?.cancel()
        showTurnOverlay = true
        
        turnOverlayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // ~1s
            if !Task.isCancelled {
                showTurnOverlay = false
            }
        }
    }
    
    // Called when the coinflip overlay confirms the starting player.
    @MainActor
    private func applyStartingTurn(_ winner: PvPTurn) {
        turn = winner
        currentRow = 0
        disabled = (winner == .player2) // if opponent starts, lock our input
        showTurnBanner(for: winner)
    }
    
    // MARK: - Coin flip (through VM)
    private func requestCoinFlipFromServer() {
        guard !coinFlipRequestInFlight else { return }
        
        coinFlipRequestInFlight = true
        coinFlipWinner = nil
        
        let thisUniqe = uniqe
        let currentMatchId = vm.currentMatchId
        let usesServer = (thisUniqe != nil && (currentMatchId?.isEmpty == false))
        
        Task {
            var winner: PvPTurn?
            
            if usesServer, let uniqe = thisUniqe, let matchId = currentMatchId {
                // Real online coin flip via backend
                winner = await vm.coinFlip(matchId: matchId, uniqe: uniqe)
            } else {
                // Preview / no real matchId: purely local random
                winner = Bool.random() ? .player1 : .player2
            }
            
            await MainActor.run {
                coinFlipRequestInFlight = false
                
                if let winner {
                    // server answered (real match) or local (preview)
                    coinFlipWinner = winner
                } else if usesServer {
                    // real match but server never answered – show error
                    print("[PVP] coinflip failed in real match – showing error")
                    showError = true
                } else {
                    // preview fallback
                    coinFlipWinner = .player1
                }
            }
        }
    }
    
    // MARK: - Error / word handling
    
    private func handleError() {
        guard !vm.fatalError else { showError = true; return }
        guard vm.word == .empty && vm.numberOfErrors > 0 else { return }
        guard let uniqe else { showError = true; return }
        
        Task { @MainActor in
            await vm.word(uniqe: uniqe, newWord: didStart)
            didStart = vm.word != .empty
        }
    }
    
    private func handleWordChange() {
        // When VM gives us a new word (e.g. from outside), reset board and show coin flip.
        resetBoard()
        disabled = true
        result = .none
        showGameEndPopup = false
        showTurnOverlay = false
        
        // reset coin flip for the new word
        coinFlipWinner = nil
        coinFlipRequestInFlight = false
        
        showCoinFlip = true
        endFetchAnimation = true
    }
    
    // MARK: - Back / navigation
    
    private func backButtonTap() {
        if endFetchAnimation {
            showExitPopup = true
        } else {
            closeView()
        }
    }
    
    @MainActor
    private func closeView() {
        UIApplication.shared.hideKeyboard()
        cancelAllTasks()
        screenManager.keepScreenOn = false
        audio.stop()
        //        session.finishRound()
        
        delayedNavTask?.cancel()
        delayedNavTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            router.navigateBack()
        }
    }
    
    private func closeViewAfterError() {
        Task { @MainActor in
            closeView()
        }
    }
    
    // MARK: - Turn logic (local player + opponent)
    
    private func isCorrectGuess(matrix: [[String]], row: Int) -> Bool {
        let guess = matrix[row].joined()
        guard !vm.wordValue.isEmpty else { return false }
        return guess.lowercased() == vm.wordValue.lowercased()
    }
    
    /// Local player finishes a row.
    /// EXACTLY ONE row per turn:
    /// - submit,
    /// - color,
    /// - notify server,
    /// - wait for `pvp:turn` from server to actually switch turn.
    private func calculatePlayer1Turn(i: Int) {
        guard turn == .player1, i == currentRow else { return }
        guard p1Matrix[i].allSatisfy({ !$0.isEmpty }) else { return }
        guard endFetchAnimation, didStart, !disabled else { return }
        guard let uniqe else { return }
        
        UIApplication.shared.hideKeyboard()
        p1Colors[i] = vm.calculateColors(with: p1Matrix[i])
        
        if isCorrectGuess(matrix: p1Matrix, row: i) {
            Task { @MainActor in
                audio.stop()
                audio.playSound(sound: "success", type: "wav")
                finishRound(as: .player1Win)
            }
        } else {
            // Tell server this row is done; it will emit pvp:turn with nextRow
            Task { @MainActor in
                disabled = true
                try? await Task.sleep(nanoseconds: 800_000_000)
                withAnimation {
                    turn = .player2
                }
                vm.notifyRowDone(uniqe: uniqe, row: i)
                // Do NOT change `turn` or `currentRow` here
            }
        }
    }
    
    /// Opponent finished a row (from THIS device's POV).
    /// We color their row locally and check win/draw.
    @MainActor
    private func handleOpponentRowComplete(row i: Int) {
        guard i >= 0 && i < rows else { return }
        guard endFetchAnimation, didStart, !vm.wordValue.isEmpty else { return }
        
        let guessRow = p2Matrix[i]
        guard guessRow.allSatisfy({ !$0.isEmpty }) else { return }
        
        p2Colors[i] = vm.calculateColors(with: guessRow)
        
        if isCorrectGuess(matrix: p2Matrix, row: i) {
            audio.stop()
            audio.playSound(sound: "fail", type: "wav")
            finishRound(as: .player2Win)
        } else if i == rows - 1 {
            // Only after *opponent* has also used their last row → draw
            audio.stop()
            audio.playSound(sound: "fail", type: "wav")
            finishRound(as: .draw)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            content()
            
            // Matching / queue overlay (FULL SCREEN, with back button)
            if isMatching {
                PvPMatchingOverlay(
                    language: language,
                    onBack: {
                        Task { @MainActor in
                            vm.leaveMatchQueue()
                            isMatching = false
                            backButtonTap()
                        }
                    }
                )
            }
            
            // Coin flip decides who starts each round
            if showCoinFlip {
                CoinFlipOverlay(
                    isPresented: $showCoinFlip,
                    startingTurn: $turn,
                    player1Image: "player_\(gender ?? "male")",
                    player2Image: "player_opponent_\(opponentGender ?? "male")",
                    language: language,
                    winner: $coinFlipWinner,
                    isRequesting: $coinFlipRequestInFlight,
                    onRequestServerFlip: {
                        // This will run automatically on BOTH devices
                        // as soon as the overlay appears.
                        requestCoinFlipFromServer()
                    },
                    onAutoStart: { winner in
                        Task { @MainActor in
                            applyStartingTurn(winner)
                        }
                    }
                )
            }
        }
        .onAppear {
            isVisible = true
            gender = loginHandeler.model?.gender ?? "male"
            opponentGender = opponentGender ?? "male"
            //            session.startNewRound(id: .pvp)
            
            guard let uniqe else {
                showError = true
                return
            }
            
            // Start matching immediately
            isMatching = true
            
            vm.startMatchQueue(
                uniqe: uniqe,
                languageCode: language,
                onWaiting: { waiting in
                    Task { @MainActor in
                        isMatching = waiting
                        print("[PVP] waiting:", waiting)
                    }
                },
                onMatchFound: { matchId, _, opponentId in
                    Task { @MainActor in
                        isMatching = false
                        print("[PVP] match found id=\(matchId) vs \(opponentId)")
                        vm.joinMatch(matchId: matchId, uniqe: uniqe)
                        await startGame(fetchNewWord: true)
                        startOpponentTypingListenerIfNeeded()
                        startTurnListenerIfNeeded(for: uniqe)
                        
                        // Listen for opponent leaving the match
                        vm.observeOpponentLeft(localPlayerId: uniqe) { _ in
                            Task { @MainActor in
                                // Stop all interaction in this match
                                disabled = true
                                showCoinFlip = false
                                showTurnOverlay = false
                                showGameEndPopup = false
                                
                                // Show “opponent left” popup – OK will close the view
                                showOpponentLeftPopup = true
                            }
                        }
                    }
                },
                onError: { reason in
                    Task { @MainActor in
                        isMatching = false
                        print("[PVP] queue error:", reason ?? "unknown")
                        showError = true
                    }
                }
            )
        }
        .onDisappear {
            isVisible = false
            screenManager.keepScreenOn = false
            audio.stop()
            cancelAllTasks()
            vm.leaveMatchQueue()
        }
        .onChange(of: vm.numberOfErrors) { handleError() }
        .onChange(of: vm.word) { handleWordChange() }
        .customAlert(
            "Exit",
            type: .info,
            isPresented: $showExitPopup,
            actionText: "OK",
            cancelButtonText: "Cancel",
            action: { Task { @MainActor in closeView() } },
            message: { Text("Are you sure?") }
        )
        .customAlert(
            "Network error",
            type: .fail,
            isPresented: $showError,
            actionText: "OK",
            action: closeViewAfterError,
            message: { Text("something went wrong") }
        )
        .customAlert(
            "Opponent left",
            type: .info,
            isPresented: $showOpponentLeftPopup,
            actionText: "OK",
            action: closeViewAfterError,
            message: { Text("Your opponent left the match.") }
        )
    }
    
    // MARK: - Layout
    
    @ViewBuilder
    private func content() -> some View {
        GeometryReader { _ in
            background()
            ZStack(alignment: .top) {
                topBar().padding(.top, 4)
                game().padding(.top, 10)
                
                PvPTurnChangeOverlay(
                    isPresented: $showTurnOverlay,
                    isPlayer2: turn == .player2,
                    language: language
                )
            }
        }
        .ignoresSafeArea(.keyboard)
    }
    
    @ViewBuilder
    private func topBar() -> some View {
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
    
    @ViewBuilder
    private func background() -> some View {
        GameViewBackground()
            .ignoresSafeArea()
    }
    
    // MARK: - Top player cards (no HP, just avatars)
    
    @ViewBuilder
    private func gameTopView() -> some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .top) {
                ZStack(alignment: .trailing) {
                    HStack {
                        Spacer()
                        
                        // Player 1 (local)
                        ZStack(alignment: .center) {
                            EmptyCard(height: 76)
                                .realisticCell(color: .dynamicBlack.opacity(0.4), cornerRadius: 8)
                                .opacity(turn == .player1 ? 1 : 0.4)
                                .frame(width: 120)
                            
                            VStack(spacing: 4) {
                                Image("player_\(gender ?? "male")")
                                    .resizable()
                                    .scaledToFill()
                                    .shadow(radius: 4)
                                    .frame(width: 46, height: 46)
                                
                                Text("You".localized)
                                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.dynamicBlack)
                            }
                            .padding(4)
                        }
                        
                        Spacer()
                        
                        // Player 2 (opponent, display-only)
                        ZStack(alignment: .center) {
                            EmptyCard(height: 76)
                                .realisticCell(color: .dynamicBlack.opacity(0.4), cornerRadius: 8)
                                .opacity(turn == .player2 ? 1 : 0.4)
                                .frame(width: 120)
                            
                            VStack(spacing: 4) {
                                Image("player_opponent_\(opponentGender ?? "male")")
                                    .resizable()
                                    .scaledToFill()
                                    .shadow(radius: 4)
                                    .frame(width: 46, height: 46)
                                
                                Text("Opponent".localized)
                                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.dynamicBlack)
                            }
                            .padding(4)
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
    
    // MARK: - Board
    
    @ViewBuilder
    private func gameTable() -> some View {
        ForEach(0..<rows, id: \.self) { i in
            ZStack {
                switch turn {
                case .player1:
                    // Active player is LOCAL on this device
                    let isActiveRow = currentRow == i
                    let gainFocus = Binding<Bool>(
                        get: {
                            !showCoinFlip &&
                            endFetchAnimation &&
                            didStart &&
                            isActiveRow &&
                            !disabled
                        },
                        set: { _ in }
                    )
                    
                    let hasPrevGuess = i > 0 && currentRow == i && p2Matrix[currentRow - 1].contains { !$0.isEmpty }
                    let placeHolderData = hasPrevGuess ? allBestGuesses : nil
                    
                    WordView(
                        cleanCells: $cleanCells,
                        current: $currentRow,
                        length: length,
                        placeHolderData: placeHolderData,
                        isSolved: .constant(
                            !vm.wordValue.isEmpty &&
                            p1Matrix[i].joined().lowercased() == vm.wordValue.lowercased()
                        ),
                        word: $p1Matrix[i],
                        gainFocus: gainFocus,
                        colors: $p1Colors[i],
                        done: { calculatePlayer1Turn(i: i) }
                    )
                    .opacity(isActiveRow ? 1 : 0.9)
                    .allowsHitTesting(isActiveRow && !disabled)
                    .disabled(!isActiveRow || disabled)
                    .shadow(radius: 4)
                    .cardFlip(degrees: turn == .player2 ? 180 : 0)
                    .onChange(of: p1Matrix[i]) {
                        // push typing updates for the active row
                        sendTypingUpdateIfNeeded(row: i)
                    }
                    
                case .player2:
                    // Active player is OPPONENT on this device.
                    // This still shows the OPPONENT board on BOTH devices,
                    // but only they have input enabled on their own device.
                    let isOpponentRow = (currentRow == i)
                    
                    WordView(
                        cleanCells: $cleanCells,
                        isAI: false, // reuse AI style for opponent
                        current: $currentRow,
                        length: length,
                        isSolved: .constant(
                            !vm.wordValue.isEmpty &&
                            p2Matrix[i].joined().lowercased() == vm.wordValue.lowercased()
                        ),
                        isCurrentRow: isOpponentRow,
                        word: $p2Matrix[i],
                        gainFocus: .constant(false),
                        colors: $p2Colors[i],
                        done: { /* opponent rows updated via network */ }
                    )
                    .opacity(isOpponentRow ? 1 : 0.9)
                    .allowsHitTesting(false)
                    .disabled(true)
                    .shadow(radius: 4)
                    .cardFlip(degrees: 180)
                }
            }
            .boardFlip(isOther: turn == .player2)
        }
    }
    
    @ViewBuilder
    private func gameBottom() -> some View {
        ZStack {
            KeyboardHeightView(adjustBy: 10)
            AppTitle(size: 50)
                .shadow(color: .black.opacity(0.12), radius: 4, x: 4, y: 4)
                .shadow(color: .white.opacity(0.12), radius: 4, x: -4 ,y: -4)
        }
    }
    
    @ViewBuilder
    private func gameBody() -> some View {
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
    
    @ViewBuilder
    private func game() -> some View {
        if uniqe != nil {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) { gameBody() }
                    .ignoresSafeArea(.keyboard)
                    .disabled(!endFetchAnimation || !didStart || vm.numberOfErrors > 0)
                    .opacity(endFetchAnimation && didStart && vm.numberOfErrors == 0 ? 1 : 0.7)
                    .grayscale(endFetchAnimation && didStart && vm.numberOfErrors == 0 ? 0 : 1)
            }
            .padding(.top, 44)
        }
    }
    
    @ViewBuilder
    func backButton() -> some View {
        BackButton(action: backButtonTap)
    }
}

// MARK: - Matching overlay (queue + back)

fileprivate struct PvPMatchingOverlay: View {
    var language: String?
    var onBack: () -> Void
    
    @Environment(\.colorScheme) private var scheme
    
    private var title: String {
        language == "he" ? "מחפש יריב..." : "Searching for opponent…"
    }
    
    private var subtitle: String {
        if language == "he" {
            return "נחפש שחקן אחר באותה שפה.\nאפשר לבטל בכל רגע."
        } else {
            return "Looking for another player in the same language.\nYou can cancel at any time."
        }
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(scheme == .dark ? 0.98 : 0.98)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(8)
                            .background(.ultraThickMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                
                Spacer()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.4)
                    
                    Text(title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    
                    Text(subtitle)
                        .font(.system(.body, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }
                
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: true)
    }
}

// MARK: - Turn Change Overlay (PVP)

fileprivate struct PvPTurnChangeOverlay: View {
    @Binding var isPresented: Bool
    var isPlayer2: Bool
    var language: String?
    @Environment(\.colorScheme) private var scheme
    
    private var direction: PvPSweepStripe.Direction {
        isPlayer2 ? .rightToLeft : .leftToRight
    }
    
    var body: some View {
        ZStack {
            if isPresented {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(scheme == .dark ? 0.12 : 0.10)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                PvPSweepStripe(accent: accent, direction: direction)
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
        isPlayer2 ? "Opponent Turn".localized : "Your Turn".localized
    }
    private var accent: Color { isPlayer2 ? .purple : .cyan }
}

// MARK: - Moving sweep stripe

fileprivate struct PvPSweepStripe: View {
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

// MARK: - Coin Flip Overlay (server-driven, auto start)

fileprivate struct CoinFlipOverlay: View {
    @Binding var isPresented: Bool
    @Binding var startingTurn: PvPTurn
    
    var player1Image: String
    var player2Image: String
    var language: String?
    
    @Binding var winner: PvPTurn?
    @Binding var isRequesting: Bool
    
    /// Called when the overlay appears – triggers a server flip on the parent.
    var onRequestServerFlip: () -> Void
    /// Called automatically a short time after we know the winner.
    var onAutoStart: (PvPTurn) -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    @State private var didAutoFlip: Bool = false
    @State private var didAutoStart: Bool = false
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 22) {
                Text("Who starts?".localized)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                
                HStack(spacing: 40) {
                    VStack(spacing: 8) {
                        Image(player1Image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text("You".localized)
                            .font(.system(.caption, design: .rounded).weight(.medium))
                    }
                    
                    VStack(spacing: 8) {
                        Image(player2Image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text("Opponent".localized)
                            .font(.system(.caption, design: .rounded).weight(.medium))
                    }
                }
                
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.yellow.opacity(0.3), .yellow.opacity(0.9)],
                                center: .center,
                                startRadius: 8, endRadius: 60
                            )
                        )
                        .frame(width: 88, height: 88)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                        .rotation3DEffect(
                            .degrees(rotation),
                            axis: (x: 0, y: 1, z: 0)
                        )
                    
                    if let winner {
                        Text(winner == .player1 ? "You start".localized : "Opponent starts".localized)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    } else if isRequesting {
                        Text("Deciding…".localized)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    } else {
                        Text("Preparing…".localized)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            )
            .padding(32)
        }
        .onAppear {
            autoFlipIfNeeded()
        }
        .onChange(of: winner) {
            autoStartIfNeeded()
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }
    
    // MARK: - Auto coin flip
    
    private func autoFlipIfNeeded() {
        guard !didAutoFlip else { return }
        didAutoFlip = true
        
        onRequestServerFlip()
        
        let spins = reduceMotion ? 1.0 : 3.0
        withAnimation(.linear(duration: 0.8)) {
            rotation += 360 * spins
        }
    }
    
    // MARK: - Auto start after winner decided
    
    private func autoStartIfNeeded() {
        guard !didAutoStart, let winner else { return }
        didAutoStart = true
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            await MainActor.run {
                startingTurn = winner
                onAutoStart(winner)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                    isPresented = false
                }
            }
        }
    }
}
