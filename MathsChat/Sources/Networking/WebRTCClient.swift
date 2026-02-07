import Foundation
import WebRTC

/// Connection state exposed to the rest of the app (decoupled from WebRTC enums).
enum PeerConnectionState {
    case new
    case connecting
    case connected
    case disconnected
    case failed
    case closed
}

class WebRTCClient: NSObject, ObservableObject {
    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var isInitiator = false

    @Published var connectionState: PeerConnectionState = .new
    @Published var dataChannelState: RTCDataChannelState = .closed

    // Callbacks
    var onMessageReceived: ((String) -> Void)?
    var onConnectionStateChanged: ((PeerConnectionState) -> Void)?
    var onLocalSDP: ((RTCSessionDescription) -> Void)?
    var onLocalCandidate: ((RTCIceCandidate) -> Void)?

    override init() {
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        super.init()
    }

    func createPeerConnection(isInitiator: Bool) {
        self.isInitiator = isInitiator
        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: [
                "stun:stun.l.google.com:19302",
                "stun:stun1.l.google.com:19302"
            ])
        ]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)

        // Only the offerer creates the data channel
        if isInitiator {
            let dcConfig = RTCDataChannelConfiguration()
            dcConfig.isOrdered = true
            dcConfig.isNegotiated = false
            dataChannel = peerConnection?.dataChannel(forLabel: "chat", configuration: dcConfig)
            dataChannel?.delegate = self
        }
    }

    func createOffer() {
        guard let peerConnection = peerConnection else { return }

        let constraints = RTCMediaConstraints(mandatoryConstraints: [
            "OfferToReceiveAudio": "false",
            "OfferToReceiveVideo": "false"
        ], optionalConstraints: nil)

        peerConnection.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp else {
                print("Error creating offer: \(error?.localizedDescription ?? "unknown")")
                return
            }

            peerConnection.setLocalDescription(sdp) { error in
                if let error = error {
                    print("Error setting local description: \(error.localizedDescription)")
                } else {
                    DispatchQueue.main.async {
                        self.onLocalSDP?(sdp)
                    }
                }
            }
        }
    }

    func createAnswer() {
        guard let peerConnection = peerConnection else { return }

        let constraints = RTCMediaConstraints(mandatoryConstraints: [
            "OfferToReceiveAudio": "false",
            "OfferToReceiveVideo": "false"
        ], optionalConstraints: nil)

        peerConnection.answer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp else {
                print("Error creating answer: \(error?.localizedDescription ?? "unknown")")
                return
            }

            peerConnection.setLocalDescription(sdp) { error in
                if let error = error {
                    print("Error setting local description: \(error.localizedDescription)")
                } else {
                    DispatchQueue.main.async {
                        self.onLocalSDP?(sdp)
                    }
                }
            }
        }
    }

    func setRemoteDescription(_ sdp: RTCSessionDescription, completion: ((Error?) -> Void)? = nil) {
        peerConnection?.setRemoteDescription(sdp) { error in
            if let error = error {
                print("Error setting remote description: \(error.localizedDescription)")
            }
            completion?(error)
        }
    }

    func addIceCandidate(_ candidate: RTCIceCandidate) {
        peerConnection?.add(candidate, completionHandler: { error in
            if let error = error {
                print("Error adding ICE candidate: \(error.localizedDescription)")
            }
        })
    }

    @discardableResult
    func sendMessage(_ text: String) -> Bool {
        guard let dataChannel = dataChannel,
              dataChannel.readyState == .open,
              let data = text.data(using: .utf8) else {
            print("Data channel not ready")
            return false
        }

        let buffer = RTCDataBuffer(data: data, isBinary: false)
        dataChannel.sendData(buffer)
        return true
    }

    func close() {
        dataChannel?.close()
        peerConnection?.close()
        dataChannel = nil
        peerConnection = nil
        DispatchQueue.main.async {
            self.connectionState = .closed
            self.dataChannelState = .closed
        }
    }

    // Map RTCIceConnectionState → our PeerConnectionState
    private func mapIceState(_ iceState: RTCIceConnectionState) -> PeerConnectionState {
        switch iceState {
        case .new:
            return .new
        case .checking:
            return .connecting
        case .connected, .completed:
            return .connected
        case .disconnected:
            return .disconnected
        case .failed:
            return .failed
        case .closed:
            return .closed
        case .count:
            return .new
        @unknown default:
            return .disconnected
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCClient: RTCPeerConnectionDelegate {

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        // Required by protocol. No action needed for chat-only usage.
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let mapped = mapIceState(newState)
        DispatchQueue.main.async {
            self.connectionState = mapped
            self.onConnectionStateChanged?(mapped)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DispatchQueue.main.async {
            self.onLocalCandidate?(candidate)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        DispatchQueue.main.async {
            self.dataChannel = dataChannel
            self.dataChannel?.delegate = self
            self.dataChannelState = dataChannel.readyState
        }
    }
}

// MARK: - RTCDataChannelDelegate

extension WebRTCClient: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        DispatchQueue.main.async {
            self.dataChannelState = dataChannel.readyState
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard !buffer.isBinary,
              let text = String(data: buffer.data, encoding: .utf8) else {
            return
        }

        DispatchQueue.main.async {
            self.onMessageReceived?(text)
        }
    }
}
