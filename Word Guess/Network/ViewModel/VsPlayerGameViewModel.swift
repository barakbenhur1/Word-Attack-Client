//  VsPlayerGameViewModel.swift
//  Word Guess / WordZap
//
//  Created by Barak Ben Hur on 15/11/2025.
//

import SwiftUI
import Alamofire
@preconcurrency import SocketIO

// Shared PVP turn type – used by both VM and View.
enum PvPTurn: Int, Codable {
    case player1 = 0
    case player2 = 1
}

@Observable
class VsPlayerGameViewModel: GameViewModel {
    private let provider: WordProvider
    private let pvpSocket: PvPSocketClient
    
    // Error / health
    private let maxErrorCount: Int
    private var errorCount: Int
    var fatalError: Bool { errorCount >= maxErrorCount }
    var numberOfErrors: Int { errorCount }
    
    // Word index tracking
    private var wordNumber: Int
    var wordCount: Int { wordNumber }
    
    // Current secret word for this round
    private var pvpWord: SimpleWord
    var word: SimpleWord { pvpWord }
    override var wordValue: String { pvpWord.value }
    
    // 🔹 PVP match metadata (needs to be the SAME on both devices)
    /// Current PVP match identifier (set by matchmaking / queue).
    var currentMatchId: String?
    /// Optional: store opponent id if you want to show it in UI.
    var opponentId: String?
    
    // MARK: - Init
    
    required override init() {
        provider       = .init()
        pvpWord        = .empty
        wordNumber     = UserDefaults.standard.integer(forKey: "pvpWordNumber")
        maxErrorCount  = 3
        errorCount     = 0
        pvpSocket      = .shared
        super.init()
    }
    
    // MARK: - Local mock word (offline / previews)
    
    func initMoc() async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            let local = LanguageSetting()
            guard let language = local.locale.identifier.components(separatedBy: "_").first
            else {
                pvpWord = .init(value: "abcde")
                return
            }
            
            guard let lang: Language = .init(rawValue: language) else {
                pvpWord = .init(value: language == "he" ? "אבגדה" : "abcde")
                return
            }
            
            // Uses GameViewModel helper
            pvpWord = .init(value: generateWord(for: lang))
        }
    }
    
    // MARK: - PVP word fetch (same word per match)
    
    /// Response shape from /pvp/word on the server.
    private struct PvpWordResponse: Decodable {
        let value: String
    }
    
    /// Fetches a PVP word tied to a specific matchId.
    /// Same `matchId` => same word on both devices.
    /// If server returns an error body (e.g. { "error": "no match found" }) we log and return nil.
    private func fetchPvpWordFromServer(
        matchId: String,
        length: Int,
        languageCode: String?
    ) async -> SimpleWord? {
        guard var components = URLComponents(string: "http://localhost:3000/pvp/word") else {
            return nil
        }
        
        var items: [URLQueryItem] = [
            .init(name: "matchId", value: matchId),
            .init(name: "length", value: String(length))
        ]
        if let languageCode {
            items.append(.init(name: "lang", value: languageCode))
        }
        components.queryItems = items
        
        guard let url = components.url else { return nil }
        
        do {
            let data = try await AF.request(url, method: .get)
                .serializingData()
                .value
            
            // Try decode success payload first
            if let decoded = try? JSONDecoder().decode(PvpWordResponse.self, from: data) {
                return SimpleWord(value: decoded.value)
            }
            
            // Try to read an error JSON: { error: "no match found" }
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let errorMessage = json["error"] as? String {
                Trace.log("🛟", "PVP /pvp/word error: \(errorMessage)", Fancy.red)
            } else if let s = String(data: data, encoding: .utf8) {
                // Fallback: raw string body
                Trace.log("🛟", "PVP /pvp/word unexpected body: \(s)", Fancy.red)
            }
            
            return nil
        } catch {
            Trace.log("🛟", "PVP /pvp/word AF error: \(error.localizedDescription)", Fancy.red)
            return nil
        }
    }
    
    // MARK: - Fetch word from backend (PVP-aware)
    
    /// Fetches a new secret word from the server.
    /// - Parameters:
    ///   - uniqe: user / device id (used by your normal WordProvider logic)
    ///   - newWord: if `false`, only loads a word without bumping the counter
    ///
    /// If `currentMatchId` is set, we call `/pvp/word?matchId=...` so
    /// **both players in that match get the SAME word**.
    /// If that fails (e.g. "no match found"), we gracefully fall back
    /// to `provider.word(uniqe:)`.
    func word(uniqe: String, newWord: Bool = true) async {
        let wordLength = DifficultyType.pvp.getLength()
        
        let local = LanguageSetting()
        let languageCode = local.locale.identifier.components(separatedBy: "_").first
        
        var value: SimpleWord? = nil
        
        if let matchId = currentMatchId, !matchId.isEmpty {
            // 🔹 PVP path: match-based word
            let pvpValue = await fetchPvpWordFromServer(
                matchId: matchId,
                length: wordLength,
                languageCode: languageCode
            )
            
            if let pvpValue {
                value = pvpValue
            } else {
                // Soft failure: log and fall back to legacy path
                Trace.log("🛟", "PVP fetch failed for matchId=\(matchId), falling back to normal word()", Fancy.yellow)
                value = await provider.word(uniqe: uniqe)
            }
        } else {
            // 🔹 Fallback path: old behavior (per-user word)
            value = await provider.word(uniqe: uniqe)
        }
        
        guard let value else {
            await handleError()
            return
        }
        
        await MainActor.run { [weak self] in
            guard let self else { return }
            Trace.log("🛟", "PVP word is \(value.value)", Fancy.mag)
            errorCount = 0
            pvpWord = value
            
            guard newWord else { return }
            increaseAndSaveWordNumber()
        }
    }
    
    // MARK: - Public: enumerate ALL per-index best merges (Y/G only, deduped)
    func perIndexCandidatesSparse(matrix: [[String]], colors: [[CharColor]],
                                  matrix2: [[String]], colors2: [[CharColor]]) -> [BestGuess] {
        return BestGuessProducerProvider.guesser.perIndexCandidatesSparse(matrix: matrix, colors: colors,
                                                                          aiMatrix: matrix2, aiColors: colors2,
                                                                          /*debug: true*/)
    }
    
    // MARK: - PVP socket helpers
    
    /// Make sure we are in the right match room on the socket server.
    func joinMatch(matchId: String, uniqe: String) {
        currentMatchId = matchId
        pvpSocket.join(matchId: matchId, playerId: uniqe)
    }
    
    /// Asks the backend (via socket) who starts the round.
    func coinFlip(matchId: String, uniqe: String) async -> PvPTurn? {
        await pvpSocket.coinFlip(matchId: matchId, uniqe: uniqe)
    }
    
    // MARK: - 🔸 Matchmaking QUEUE → this is where matchId is retrieved
    
    func startMatchQueue(
        uniqe: String,
        languageCode: String?,
        onWaiting: ((Bool) -> Void)? = nil,
        onMatchFound: @escaping (_ matchId: String, _ youId: String, _ opponentId: String) -> Void,
        onError: ((String?) -> Void)? = nil
    ) {
        pvpSocket.joinQueue(
            playerId: uniqe,
            languageCode: languageCode,
            onWaiting: onWaiting,
            onMatchFound: { [weak self] matchId, youId, opponentId in
                guard let self else { return }
                
                Task { @MainActor in
                    self.currentMatchId = matchId
                    self.opponentId = opponentId
                    onMatchFound(matchId, youId, opponentId)
                }
            },
            onError: { reason in
                Task { @MainActor in
                    onError?(reason)
                }
            }
        )
    }
    
    func leaveMatchQueue() {
        pvpSocket.leaveQueue()
        currentMatchId = nil
        opponentId = nil
    }
    
    // MARK: - Typing helpers
    
    func sendTypingUpdate(
        uniqe: String,
        row: Int,
        guess: String
    ) {
        guard let matchId = currentMatchId, !matchId.isEmpty else { return }
        pvpSocket.sendTyping(
            matchId: matchId,
            playerId: uniqe,
            rowIndex: row,
            guess: guess
        )
    }
    
    func observeOpponentTyping(
        onTyping: @escaping (_ rowIndex: Int, _ guess: String) -> Void
    ) {
        guard let matchId = currentMatchId, !matchId.isEmpty else { return }
        
        pvpSocket.observeTypingEvents { incomingMatchId, _, rowIndex, guess in
            guard incomingMatchId == matchId else { return }
            
            Task { @MainActor in
                onTyping(rowIndex, guess)
            }
        }
    }
    
    // MARK: - Turn changes (row based)
    
    func observeTurnChanges(
        localPlayerId: String,
        onTurn: @escaping (_ isMyTurn: Bool, _ nextRow: Int) -> Void
    ) {
        pvpSocket.observeTurnEvents { [weak self] matchId, nextPlayerId, nextRow in
            guard let self else { return }
            guard matchId == self.currentMatchId else { return }
            guard let nextPlayerId else { return }
            
            let isMine = (nextPlayerId == localPlayerId)
            Task { @MainActor in
                onTurn(isMine, nextRow)
            }
        }
    }
    
    func notifyRowDone(uniqe: String, row: Int) {
        guard let matchId = currentMatchId, !matchId.isEmpty else { return }
        pvpSocket.sendRowDone(
            matchId: matchId,
            playerId: uniqe,
            rowIndex: row
        )
    }
    
    // MARK: - Opponent left

    func observeOpponentLeft(
        localPlayerId: String,
        onOpponentLeft: @escaping (_ opponentId: String) -> Void
    ) {
        pvpSocket.observePlayerLeft { playerId in
            guard playerId != localPlayerId else { return }
            
            Task { @MainActor in
                onOpponentLeft(playerId)
            }
        }
    }
    
    // MARK: - Error / counters
    
    @MainActor
    private func handleError() {
        errorCount += 1
        pvpWord = .empty
    }
    
    @MainActor
    private func increaseAndSaveWordNumber() {
        guard pvpWord != .empty else { return }
        wordNumber += 1
        UserDefaults.standard.set(wordNumber, forKey: "pvpWordNumber")
    }
}

// MARK: - PvPSocketClient (Socket.IO wrapper)

final class PvPSocketClient {
    static let shared = PvPSocketClient()
    
    private let manager: SocketManager
    private let socket: SocketIOClient
    
    private var isConnected = false
    
    // Queue callbacks
    private var queueMatchHandler: ((String, String, String) -> Void)?
    private var queueWaitingHandler: ((Bool) -> Void)?
    private var queueErrorHandler: ((String?) -> Void)?
    
    // Typing callback: (matchId, fromPlayerId, rowIndex, guess)
    private var typingHandler: ((String, String, Int, String) -> Void)?
    
    // Turn callback: (matchId, nextPlayerId?, nextRow)
    private var turnHandler: ((String, String?, Int) -> Void)?
    
    // Player-left callback: (matchId, playerId)
    private var playerLeftHandler: ((String) -> Void)?
    
    private var pendingQueueJoinPayload: [String: Any]?
    
    private init() {
        let url = URL(string: "http://localhost:3000" /* prod URL here */)!
        manager = SocketManager(
            socketURL: url,
            config: [
                .log(true),
                .compress,
                .reconnects(true),
                .reconnectAttempts(-1),
                .reconnectWait(2)
            ]
        )
        socket = manager.defaultSocket
        configureBaseHandlers()
    }
    
    private func configureBaseHandlers() {
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.isConnected = true
            print("[PVP] socket connected:", self.socket.sid ?? "(no sid)")
            
            if let payload = self.pendingQueueJoinPayload {
                let pid = payload["playerId"] as? String ?? "?"
                let lang = payload["lang"] as? String ?? "?"
                print("[PVP] late emit pvp:queue:join playerId=\(pid) lang=\(lang)")
                self.socket.emit("pvp:queue:join", payload)
            }
        }
        
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            guard let self else { return }
            self.isConnected = false
            print("[PVP] socket disconnected")
        }
        
        socket.on(clientEvent: .error) { data, _ in
            print("[PVP] socket error:", data)
        }
        
        socket.on("pvp:error") { data, _ in
            print("[PVP] server error:", data)
        }
    }
    
    private func connectIfNeeded() {
        if !isConnected && socket.status != .connected && socket.status != .connecting {
            print("[PVP] connecting socket... (status=\(socket.status.rawValue))")
            socket.connect()
        }
    }
    
    func join(matchId: String, playerId: String) {
        connectIfNeeded()
        
        let payload: [String: Any] = [
            "matchId": matchId,
            "playerId": playerId
        ]
        
        socket.emit("pvp:join", payload)
        print("[PVP] emit pvp:join matchId=\(matchId) playerId=\(playerId)")
    }
    
    func coinFlip(matchId: String, uniqe: String) async -> PvPTurn? {
        await withCheckedContinuation { continuation in
            var didResume = false
            func resumeOnce(_ value: PvPTurn?) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
            }

            let ticket = Int.random(in: 0 ... Int.max)

            let handlerId = socket.on("pvp:coinflipResult") { [weak self] data, _ in
                guard let self else { return }
                guard let dict = data.first as? [String: Any] else { return }
                guard let resMatchId = dict["matchId"] as? String,
                      resMatchId == matchId else { return }

                guard let youStart = dict["youStart"] as? Bool else {
                    print("[PVP] coinflipResult missing youStart")
                    return
                }

                print("[PVP] coinflipResult match=\(resMatchId) youStart=\(youStart)")
                self.socket.off(id: handlerId)

                let turn: PvPTurn = youStart ? .player1 : .player2
                resumeOnce(turn)
            }

            let payload: [String: Any] = [
                "matchId": matchId,
                "playerId": uniqe,
                "ticket": ticket
            ]

            print("[PVP] emit pvp:coinflip matchId=\(matchId) playerId=\(uniqe) ticket=\(ticket)")
            socket.emit("pvp:coinflip", payload)

            let socket = self.socket
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                socket.off(id: handlerId)
                resumeOnce(nil)
            }
        }
    }
    
    func sendTyping(
        matchId: String,
        playerId: String,
        rowIndex: Int,
        guess: String
    ) {
        connectIfNeeded()
        
        let payload: [String: Any] = [
            "matchId": matchId,
            "playerId": playerId,
            "row": rowIndex,
            "guess": guess
        ]
        
        print("[PVP] emit pvp:typing matchId=\(matchId) playerId=\(playerId) row=\(rowIndex) guess=\(guess)")
        socket.emit("pvp:typing", payload)
    }
    
    func observeTypingEvents(
        _ handler: @escaping (_ matchId: String, _ fromPlayerId: String, _ rowIndex: Int, _ guess: String) -> Void
    ) {
        connectIfNeeded()
        typingHandler = handler
        
        socket.off("pvp:typing")
        
        socket.on("pvp:typing") { [weak self] data, _ in
            guard let self else { return }
            guard let dict = data.first as? [String: Any] else {
                print("[PVP] pvp:typing malformed payload:", data)
                return
            }
            
            guard
                let matchId = dict["matchId"] as? String,
                let fromPlayerId = dict["playerId"] as? String,
                let rowIndex = dict["row"] as? Int,
                let guess = dict["guess"] as? String
            else {
                print("[PVP] pvp:typing missing fields:", dict)
                return
            }
            
            self.typingHandler?(matchId, fromPlayerId, rowIndex, guess)
        }
    }
    
    func sendRowDone(
        matchId: String,
        playerId: String,
        rowIndex: Int
    ) {
        connectIfNeeded()
        
        let payload: [String: Any] = [
            "matchId": matchId,
            "playerId": playerId,
            "row": rowIndex
        ]
        
        print("[PVP] emit pvp:rowDone matchId=\(matchId) playerId=\(playerId) row=\(rowIndex)")
        socket.emit("pvp:rowDone", payload)
    }
    
    func observeTurnEvents(
        _ handler: @escaping (_ matchId: String, _ nextPlayerId: String?, _ nextRow: Int) -> Void
    ) {
        connectIfNeeded()
        turnHandler = handler
        
        socket.off("pvp:turn")
        
        socket.on("pvp:turn") { [weak self] data, _ in
            guard let self else { return }
            guard let dict = data.first as? [String: Any] else {
                print("[PVP] pvp:turn malformed payload:", data)
                return
            }
            
            let matchId      = dict["matchId"] as? String ?? ""
            let nextPlayerId = dict["nextPlayerId"] as? String
            let nextRow      = dict["nextRow"] as? Int ?? 0
            
            print("[PVP] turn event matchId=\(matchId) nextPlayerId=\(nextPlayerId ?? "nil") row=\(nextRow)")
            self.turnHandler?(matchId, nextPlayerId, nextRow)
        }
    }
    
    func observePlayerLeft(
        _ handler: @escaping (_ playerId: String) -> Void
    ) {
        connectIfNeeded()
        playerLeftHandler = handler
        
        socket.off("pvp:playerLeft")
        
        socket.on("pvp:playerLeft") { [weak self] data, _ in
            guard let self else { return }
            guard let dict = data.first as? [String: Any] else {
                print("[PVP] pvp:playerLeft malformed payload:", data)
                return
            }
            
            guard let playerId = dict["playerId"] as? String else {
                print("[PVP] pvp:playerLeft missing playerId:", dict)
                return
            }
            
            print("[PVP] playerLeft playerId=\(playerId)")
            self.playerLeftHandler?(playerId)
        }
    }
    
    func joinQueue(
        playerId: String,
        languageCode: String?,
        onWaiting: ((Bool) -> Void)? = nil,
        onMatchFound: @escaping (_ matchId: String, _ youId: String, _ opponentId: String) -> Void,
        onError: ((String?) -> Void)? = nil
    ) {
        connectIfNeeded()
        
        queueMatchHandler = onMatchFound
        queueWaitingHandler = onWaiting
        queueErrorHandler = onError
        
        socket.off("pvp:matchFound")
        socket.off("pvp:queue:waiting")
        socket.off("pvp:opponentLeft")
        
        socket.on("pvp:matchFound") { [weak self] data, _ in
            guard let self else { return }
            guard
                let payload = data.first as? [String: Any],
                let matchId = payload["matchId"] as? String,
                let youId = payload["you"] as? String,
                let opponentId = payload["opponentId"] as? String
            else {
                print("[PVP] pvp:matchFound malformed payload:", data)
                return
            }
            print("[PVP] matchFound matchId=\(matchId) you=\(youId) opponent=\(opponentId)")
            self.queueMatchHandler?(matchId, youId, opponentId)
        }
        
        socket.on("pvp:queue:waiting") { [weak self] data, _ in
            guard let self else { return }
            let waiting = (data.first as? [String: Any])?["waiting"] as? Bool ?? true
            print("[PVP] queue:waiting waiting=\(waiting)")
            self.queueWaitingHandler?(waiting)
        }
        
        socket.on("pvp:opponentLeft") { [weak self] data, _ in
            guard let self else { return }
            guard let dict = data.first as? [String: Any] else {
                print("[PVP] queue pvp:opponentLeft malformed payload:", data)
                return
            }
            
            if dict["playerId"] != nil {
                print("[PVP] queue handler saw match-level opponentLeft, ignoring here:", dict)
                return
            }
            
            let reason = dict["reason"] as? String
            print("[PVP] opponentLeft (queue) reason=\(reason ?? "unknown")")
            self.queueErrorHandler?(reason ?? "Opponent left")
        }
        
        let lang = (languageCode ?? "en").lowercased()
        let payload: [String: Any] = [
            "playerId": playerId,
            "lang": lang
        ]
        
        pendingQueueJoinPayload = payload
        
        if isConnected && socket.status == .connected {
            print("[PVP] emit pvp:queue:join playerId=\(playerId) lang=\(lang)")
            socket.emit("pvp:queue:join", payload)
        } else {
            print("[PVP] queue join requested before connect, will emit when connected")
            socket.once(clientEvent: .connect) { [weak self] _, _ in
                guard let self else { return }
                guard let payload = self.pendingQueueJoinPayload else { return }
                let pid = payload["playerId"] as? String ?? "?"
                let lg  = payload["lang"] as? String ?? "?"
                print("[PVP] (on connect) emit pvp:queue:join playerId=\(pid) lang=\(lg)")
                self.socket.emit("pvp:queue:join", payload)
            }
        }
    }
    
    func leaveQueue() {
        connectIfNeeded()
        pendingQueueJoinPayload = nil
        print("[PVP] emit pvp:queue:leave")
        socket.emit("pvp:queue:leave")
    }
}

extension SocketIOClient: @unchecked @retroactive Sendable {}
