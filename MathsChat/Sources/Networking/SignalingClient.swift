import Foundation
import Combine

class SignalingClient: NSObject, ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let config: ConnectionConfig
    private var pendingJoin = false

    @Published var isConnected = false
    @Published var roomPeers = 0

    // Callbacks
    var onPeerJoined: (() -> Void)?
    var onPeerLeft: (() -> Void)?
    var onRelayedPayload: ((SignalingPayload) -> Void)?
    var onError: ((String) -> Void)?

    init(config: ConnectionConfig) {
        self.config = config
        super.init()
    }

    func connect() {
        guard let url = URL(string: config.signalingServer) else {
            onError?("Invalid signaling server URL")
            return
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        self.urlSession = session

        task.resume()
        receiveMessage()

        // Join room after socket opens
        pendingJoin = true
    }

    func disconnect() {
        send(action: "leave", room: config.roomCode)
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        pendingJoin = false
    }

    func send(action: String, room: String? = nil, payload: SignalingPayload? = nil) {
        guard let task = webSocketTask else { return }

        let message = SignalingMessage(action: action, room: room, payload: payload)
        guard let data = try? JSONEncoder().encode(message),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        task.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.onError?("Send error: \(error.localizedDescription)")
                }
            }
        }
    }

    func relay(payload: SignalingPayload) {
        send(action: "relay", room: config.roomCode, payload: payload)
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage() // Continue receiving

            case .failure(let error):
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.onError?("WebSocket error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(SignalingMessage.self, from: data) else {
            return
        }

        DispatchQueue.main.async {
            switch message.action {
            case "joined":
                self.isConnected = true
                self.roomPeers = message.peers ?? 0
                if self.roomPeers == 2 {
                    self.onPeerJoined?()
                }

            case "peer_joined":
                self.roomPeers = 2
                self.onPeerJoined?()

            case "peer_left":
                self.roomPeers = max(0, self.roomPeers - 1)
                self.onPeerLeft?()

            case "relayed":
                if let payload = message.payload {
                    self.onRelayedPayload?(payload)
                }

            case "error":
                self.onError?(message.error ?? "Unknown error")

            default:
                break
            }
        }
    }
}

extension SignalingClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            if self.pendingJoin {
                self.send(action: "join", room: self.config.roomCode)
                self.pendingJoin = false
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}
