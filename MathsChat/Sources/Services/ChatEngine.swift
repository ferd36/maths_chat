import Foundation
import Combine
import WebRTC

class ChatEngine: ObservableObject {
    private var signalingClient: SignalingClient?
    private var webRTCClient: WebRTCClient?
    private var config: ConnectionConfig
    private var isInitiator = false
    private var isRemoteDescriptionSet = false
    private var pendingIceCandidates: [RTCIceCandidate] = []

    @Published var messages: [ChatMessage] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var isTyping = false
    @Published var peerDisplayName = "Peer"
    @Published var localIsTyping = false
    private var typingStopWorkItem: DispatchWorkItem?
    private var peerTypingTimeoutWorkItem: DispatchWorkItem?

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    init(config: ConnectionConfig) {
        self.config = config
    }

    func connect(with config: ConnectionConfig, isInitiator: Bool) {
        self.config = config
        self.isInitiator = isInitiator
        connectionState = .connecting
        isRemoteDescriptionSet = false
        pendingIceCandidates.removeAll()

        // Setup WebRTC
        webRTCClient = WebRTCClient()
        webRTCClient?.onLocalSDP = { [weak self] sdp in
            self?.handleLocalSDP(sdp)
        }
        webRTCClient?.onLocalCandidate = { [weak self] candidate in
            self?.handleLocalCandidate(candidate)
        }
        webRTCClient?.onMessageReceived = { [weak self] text in
            self?.handleReceivedMessage(text)
        }
        webRTCClient?.onConnectionStateChanged = { [weak self] state in
            self?.handleConnectionStateChange(state)
        }
        webRTCClient?.createPeerConnection(isInitiator: isInitiator)

        // Setup signaling
        signalingClient = SignalingClient(config: config)
        signalingClient?.onPeerJoined = { [weak self] in
            self?.handlePeerJoined()
        }
        signalingClient?.onPeerLeft = { [weak self] in
            self?.handlePeerLeft()
        }
        signalingClient?.onRelayedPayload = { [weak self] payload in
            self?.handleRelayedPayload(payload)
        }
        signalingClient?.onError = { error in
            print("Signaling error: \(error)")
        }
        signalingClient?.connect()
    }

    func disconnect() {
        signalingClient?.disconnect()
        webRTCClient?.close()
        connectionState = .disconnected
        isRemoteDescriptionSet = false
        pendingIceCandidates.removeAll()
    }

    func sendMessage(_ text: String) {
        let message = ChatMessage(senderID: "me", text: text, status: .sending)
        messages.append(message)

        // Create wire message
        let wireMsg = WireMessage(
            type: "message",
            id: message.id.uuidString,
            text: text,
            timestamp: ISO8601DateFormatter().string(from: message.timestamp)
        )

        guard let jsonData = try? JSONEncoder().encode(wireMsg),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            updateMessageStatus(id: message.id, status: .failed)
            return
        }

        let didSend = webRTCClient?.sendMessage(jsonString) ?? false
        updateMessageStatus(id: message.id, status: didSend ? .sent : .failed)
        sendTyping(isTyping: false)
    }

    func userDidType() {
        sendTyping(isTyping: true)
        typingStopWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.sendTyping(isTyping: false)
        }
        typingStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func handlePeerJoined() {
        if isInitiator {
            webRTCClient?.createOffer()
        }
    }

    private func handleLocalSDP(_ sdp: RTCSessionDescription) {
        let typeString = RTCSessionDescription.string(for: sdp.type)
        let payload = SignalingPayload(
            type: typeString,
            sdp: sdp.sdp
        )
        signalingClient?.relay(payload: payload)
    }

    private func handleLocalCandidate(_ candidate: RTCIceCandidate) {
        let payload = SignalingPayload(
            type: "candidate",
            candidate: candidate.sdp,
            sdpMLineIndex: candidate.sdpMLineIndex,
            sdpMid: candidate.sdpMid
        )
        signalingClient?.relay(payload: payload)
    }

    private func handleRelayedPayload(_ payload: SignalingPayload) {
        if payload.type == "offer" || payload.type == "answer" {
            guard let sdp = payload.sdp else { return }
            let sdpType = RTCSessionDescription.type(for: payload.type)
            let sessionDescription = RTCSessionDescription(type: sdpType, sdp: sdp)
            let isOffer = payload.type == "offer"

            webRTCClient?.setRemoteDescription(sessionDescription) { [weak self] error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error setting remote description: \(error.localizedDescription)")
                        return
                    }
                    self.isRemoteDescriptionSet = true
                    self.flushPendingCandidates()
                    if isOffer {
                        self.webRTCClient?.createAnswer()
                    }
                }
            }
        } else if payload.type == "candidate" {
            guard let candidateSdp = payload.candidate,
                  let sdpMLineIndex = payload.sdpMLineIndex,
                  let sdpMid = payload.sdpMid else { return }
            let candidate = RTCIceCandidate(
                sdp: candidateSdp,
                sdpMLineIndex: sdpMLineIndex,
                sdpMid: sdpMid
            )
            if isRemoteDescriptionSet {
                webRTCClient?.addIceCandidate(candidate)
            } else {
                pendingIceCandidates.append(candidate)
            }
        }
    }

    private func handleReceivedMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let wireMsg = try? JSONDecoder().decode(WireMessage.self, from: data) else {
            return
        }

        if wireMsg.type == "message", let messageText = wireMsg.text {
            let message = ChatMessage(
                id: UUID(uuidString: wireMsg.id ?? "") ?? UUID(),
                senderID: "peer",
                text: messageText,
                timestamp: ISO8601DateFormatter().date(from: wireMsg.timestamp ?? "") ?? Date(),
                status: .delivered
            )
            messages.append(message)

            // Send ack
            let ack = WireMessage(type: "ack", id: wireMsg.id)
            if let ackData = try? JSONEncoder().encode(ack),
               let ackString = String(data: ackData, encoding: .utf8) {
                webRTCClient?.sendMessage(ackString)
            }
        } else if wireMsg.type == "ack", let ackId = wireMsg.id,
                  let uuid = UUID(uuidString: ackId) {
            updateMessageStatus(id: uuid, status: .delivered)
        } else if wireMsg.type == "typing" {
            let peerTyping = wireMsg.isTyping ?? false
            isTyping = peerTyping
            peerTypingTimeoutWorkItem?.cancel()
            if peerTyping {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.isTyping = false
                }
                peerTypingTimeoutWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
            }
        }
    }

    private func handleConnectionStateChange(_ state: PeerConnectionState) {
        switch state {
        case .new:
            break // keep current state
        case .connecting:
            connectionState = .connecting
        case .connected:
            connectionState = .connected
        case .disconnected, .failed, .closed:
            connectionState = .disconnected
        }
    }

    private func handlePeerLeft() {
        connectionState = .disconnected
        isTyping = false
        peerTypingTimeoutWorkItem?.cancel()
    }

    private func updateMessageStatus(id: UUID, status: ChatMessage.DeliveryStatus) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].updateStatus(status)
        }
    }

    private func sendTyping(isTyping: Bool) {
        guard localIsTyping != isTyping else { return }
        localIsTyping = isTyping
        let typingMsg = WireMessage(type: "typing", isTyping: isTyping)
        if let data = try? JSONEncoder().encode(typingMsg),
           let text = String(data: data, encoding: .utf8) {
            webRTCClient?.sendMessage(text)
        }
    }

    private func flushPendingCandidates() {
        guard !pendingIceCandidates.isEmpty else { return }
        for candidate in pendingIceCandidates {
            webRTCClient?.addIceCandidate(candidate)
        }
        pendingIceCandidates.removeAll()
    }
}
