//
//  NativePvPWebSocketClient.swift
//  WordZap
//
//  Native Cloudflare Durable Object transport. The current production build
//  still uses Socket.IO/Render; PvPSocketClient switches to this transport
//  automatically only after the API base URL is cut over to workers.dev.
//

import Foundation

final class NativePvPWebSocketClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    static let shared = NativePvPWebSocketClient()

    private let stateQueue = DispatchQueue(label: "com.barak.wordzap.pvp-native")
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var isConnected = false
    private var disconnectRequested = false
    private var pendingEvents: [(String, [String: Any])] = []
    private var desiredQueuePayload: [String: Any]?
    private var activeMatchPayload: [String: Any]?

    private var queueMatchHandler: ((String, String, String) -> Void)?
    private var queueWaitingHandler: ((Bool) -> Void)?
    private var queueErrorHandler: ((String?) -> Void)?
    private var typingHandler: ((String, String, Int, String) -> Void)?
    private var turnHandler: ((String, String?, Int) -> Void)?
    private var playerLeftHandler: ((String) -> Void)?

    private var coinFlipToken: UUID?
    private var coinFlipMatchId: String?
    private var coinFlipCompletion: ((PvPTurn?) -> Void)?

    private override init() {
        super.init()
    }

    func join(matchId: String, playerId: String) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            let payload: [String: Any] = [
                "matchId": matchId,
                "playerId": playerId
            ]
            activeMatchPayload = payload
            connectIfNeededLocked()
            sendEventLocked("pvp:join", payload)
        }
    }

    func coinFlip(matchId: String, uniqe: String) async -> PvPTurn? {
        await withCheckedContinuation { continuation in
            let token = UUID()
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                if let completion = coinFlipCompletion {
                    completion(nil)
                }

                coinFlipToken = token
                coinFlipMatchId = matchId
                coinFlipCompletion = { value in
                    continuation.resume(returning: value)
                }

                connectIfNeededLocked()
                sendEventLocked("pvp:coinflip", [
                    "matchId": matchId,
                    "playerId": uniqe,
                    "ticket": Int.random(in: 0 ... Int.max)
                ])

                stateQueue.asyncAfter(deadline: .now() + 8) { [weak self] in
                    guard let self, coinFlipToken == token else { return }
                    finishCoinFlipLocked(nil)
                }
            }
        }
    }

    func sendTyping(matchId: String, playerId: String, rowIndex: Int, guess: String) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            connectIfNeededLocked()
            sendEventLocked("pvp:typing", [
                "matchId": matchId,
                "playerId": playerId,
                "row": rowIndex,
                "guess": guess
            ])
        }
    }

    func observeTypingEvents(
        _ handler: @escaping (_ matchId: String, _ fromPlayerId: String, _ rowIndex: Int, _ guess: String) -> Void
    ) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            typingHandler = handler
            connectIfNeededLocked()
        }
    }

    func sendRowDone(matchId: String, playerId: String, rowIndex: Int) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            connectIfNeededLocked()
            sendEventLocked("pvp:rowDone", [
                "matchId": matchId,
                "playerId": playerId,
                "row": rowIndex
            ])
        }
    }

    func observeTurnEvents(
        _ handler: @escaping (_ matchId: String, _ nextPlayerId: String?, _ nextRow: Int) -> Void
    ) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            turnHandler = handler
            connectIfNeededLocked()
        }
    }

    func observePlayerLeft(_ handler: @escaping (_ playerId: String) -> Void) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            playerLeftHandler = handler
            connectIfNeededLocked()
        }
    }

    func joinQueue(
        playerId: String,
        languageCode: String?,
        onWaiting: ((Bool) -> Void)? = nil,
        onMatchFound: @escaping (_ matchId: String, _ youId: String, _ opponentId: String) -> Void,
        onError: ((String?) -> Void)? = nil
    ) {
        stateQueue.async { [weak self] in
            guard let self else { return }

            queueMatchHandler = onMatchFound
            queueWaitingHandler = onWaiting
            queueErrorHandler = onError

            let payload: [String: Any] = [
                "playerId": playerId,
                "lang": (languageCode ?? "en").lowercased()
            ]
            desiredQueuePayload = payload

            connectIfNeededLocked()
            sendEventLocked("pvp:queue:join", payload)
        }
    }

    func leaveQueue(disconnect: Bool = false) {
        stateQueue.async { [weak self] in
            guard let self else { return }

            desiredQueuePayload = nil
            activeMatchPayload = nil
            pendingEvents.removeAll { $0.0 == "pvp:queue:join" || $0.0 == "pvp:join" }

            if isConnected {
                sendEventLocked("pvp:queue:leave", [:])
            }

            guard disconnect else { return }

            queueMatchHandler = nil
            queueWaitingHandler = nil
            queueErrorHandler = nil
            typingHandler = nil
            turnHandler = nil
            playerLeftHandler = nil
            finishCoinFlipLocked(nil)
            disconnectLocked()
        }
    }

    // MARK: - Connection

    private func connectIfNeededLocked() {
        guard webSocketTask == nil else { return }
        guard let url = BackendConfiguration.pvpWebSocketURL else {
            queueErrorHandler?("Invalid PVP WebSocket URL")
            return
        }

        disconnectRequested = false
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        beginReceiveLoopLocked(task)
        print("[PVP/native] connecting:", url.absoluteString)
    }

    private func disconnectLocked() {
        disconnectRequested = true
        isConnected = false
        pendingEvents.removeAll()
        receiveTask?.cancel()
        receiveTask = nil

        let task = webSocketTask
        webSocketTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        print("[PVP/native] disconnected")
    }

    private func beginReceiveLoopLocked(_ task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self, weak task] in
            guard let task else { return }

            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self else { return }
                    self.stateQueue.async { [weak self] in
                        self?.handleMessageLocked(message)
                    }
                } catch {
                    guard let self else { return }
                    self.stateQueue.async { [weak self] in
                        self?.handleReceiveFailureLocked(task: task, error: error)
                    }
                    return
                }
            }
        }
    }

    private func handleReceiveFailureLocked(task: URLSessionWebSocketTask, error: Error) {
        guard webSocketTask === task else { return }

        isConnected = false
        webSocketTask = nil
        receiveTask?.cancel()
        receiveTask = nil

        guard !disconnectRequested else { return }

        print("[PVP/native] receive failed:", error.localizedDescription)

        if let payload = desiredQueuePayload {
            scheduleReconnectLocked(event: "pvp:queue:join", payload: payload)
        } else if let payload = activeMatchPayload {
            // The Durable Object keeps the match alive for a short grace
            // window. Reconnect with the stable match/player identity so the
            // new WebSocket replaces the stale peer without restarting PVP.
            scheduleReconnectLocked(event: "pvp:join", payload: payload)
        } else {
            queueErrorHandler?("Connection lost")
        }
    }

    private func scheduleReconnectLocked(event: String, payload: [String: Any]) {
        pendingEvents.removeAll { $0.0 == event }
        pendingEvents.append((event, payload))
        stateQueue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !disconnectRequested, webSocketTask == nil else { return }
            connectIfNeededLocked()
        }
    }

    private func sendEventLocked(_ event: String, _ data: [String: Any]) {
        guard isConnected, let task = webSocketTask else {
            pendingEvents.append((event, data))
            return
        }

        sendNowLocked(task: task, event: event, data: data)
    }

    private func sendNowLocked(task: URLSessionWebSocketTask, event: String, data: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(["event": event, "data": data]),
              let bytes = try? JSONSerialization.data(withJSONObject: ["event": event, "data": data]),
              let text = String(data: bytes, encoding: .utf8)
        else {
            queueErrorHandler?("Unable to encode PVP event")
            return
        }

        Task {
            do {
                try await task.send(.string(text))
            } catch {
                print("[PVP/native] send failed:", error.localizedDescription)
            }
        }
    }

    private func flushPendingLocked() {
        guard isConnected, let task = webSocketTask else { return }

        let events = pendingEvents
        pendingEvents.removeAll()
        for (event, data) in events {
            sendNowLocked(task: task, event: event, data: data)
        }
    }

    // MARK: - Messages

    private func handleMessageLocked(_ message: URLSessionWebSocketTask.Message) {
        let raw: String
        switch message {
        case .string(let value):
            raw = value
        case .data(let value):
            guard let string = String(data: value, encoding: .utf8) else { return }
            raw = string
        @unknown default:
            return
        }

        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String
        else {
            print("[PVP/native] malformed message:", raw)
            return
        }

        let payload = object["data"] as? [String: Any] ?? [:]

        switch event {
        case "welcome":
            break

        case "pvp:queue:waiting":
            queueWaitingHandler?(payload["waiting"] as? Bool ?? true)

        case "pvp:matchFound":
            guard let matchId = payload["matchId"] as? String,
                  let you = payload["you"] as? String,
                  let opponentId = payload["opponentId"] as? String
            else { return }
            desiredQueuePayload = nil
            queueMatchHandler?(matchId, you, opponentId)

        case "pvp:reconnected":
            print("[PVP/native] match reconnected:", payload["matchId"] as? String ?? "unknown")

        case "pvp:peerReconnecting":
            print("[PVP/native] opponent reconnect grace:", payload)

        case "pvp:coinflipResult":
            guard let matchId = payload["matchId"] as? String,
                  matchId == coinFlipMatchId,
                  let youStart = payload["youStart"] as? Bool
            else { return }
            finishCoinFlipLocked(youStart ? .player1 : .player2)

        case "pvp:typing":
            guard let matchId = payload["matchId"] as? String,
                  let playerId = payload["playerId"] as? String,
                  let row = payload["row"] as? Int,
                  let guess = payload["guess"] as? String
            else { return }
            typingHandler?(matchId, playerId, row, guess)

        case "pvp:turn":
            let matchId = payload["matchId"] as? String ?? ""
            let nextPlayerId = payload["nextPlayerId"] as? String
            let nextRow = payload["nextRow"] as? Int ?? 0
            turnHandler?(matchId, nextPlayerId, nextRow)

        case "pvp:opponentLeft":
            if let playerId = payload["playerId"] as? String {
                playerLeftHandler?(playerId)
            } else {
                queueErrorHandler?(payload["reason"] as? String ?? "Opponent left")
            }

        case "pvp:error":
            queueErrorHandler?(payload["message"] as? String ?? "PVP server error")

        default:
            print("[PVP/native] unhandled event:", event)
        }
    }

    private func finishCoinFlipLocked(_ value: PvPTurn?) {
        let completion = coinFlipCompletion
        coinFlipToken = nil
        coinFlipMatchId = nil
        coinFlipCompletion = nil
        completion?(value)
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        stateQueue.async { [weak self] in
            guard let self, self.webSocketTask === webSocketTask else { return }
            isConnected = true
            print("[PVP/native] connected")
            flushPendingLocked()
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        stateQueue.async { [weak self] in
            guard let self, self.webSocketTask === webSocketTask else { return }
            isConnected = false
            self.webSocketTask = nil
            receiveTask?.cancel()
            receiveTask = nil

            guard !disconnectRequested else { return }

            let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
            print("[PVP/native] closed code=\(closeCode.rawValue) reason=\(reasonText ?? "none")")
            if let payload = desiredQueuePayload {
                scheduleReconnectLocked(event: "pvp:queue:join", payload: payload)
            } else if let payload = activeMatchPayload {
                scheduleReconnectLocked(event: "pvp:join", payload: payload)
            } else {
                queueErrorHandler?("Connection lost")
            }
        }
    }
}
