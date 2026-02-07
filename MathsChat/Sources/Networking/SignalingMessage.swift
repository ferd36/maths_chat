import Foundation

// Signaling protocol messages (WebSocket JSON)
struct SignalingMessage: Codable {
    let action: String
    let room: String?
    let payload: SignalingPayload?
    let peers: Int?
    let error: String?

    init(action: String, room: String? = nil, payload: SignalingPayload? = nil, peers: Int? = nil, error: String? = nil) {
        self.action = action
        self.room = room
        self.payload = payload
        self.peers = peers
        self.error = error
    }
}

struct SignalingPayload: Codable {
    let type: String
    let sdp: String?
    let candidate: String?
    let sdpMLineIndex: Int32?
    let sdpMid: String?

    init(type: String, sdp: String? = nil, candidate: String? = nil, sdpMLineIndex: Int32? = nil, sdpMid: String? = nil) {
        self.type = type
        self.sdp = sdp
        self.candidate = candidate
        self.sdpMLineIndex = sdpMLineIndex
        self.sdpMid = sdpMid
    }
}
