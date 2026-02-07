import Foundation

struct ConnectionConfig: Codable {
    var signalingServer: String    // WebSocket URL
    var roomCode: String
    var displayName: String

    init(signalingServer: String = "ws://localhost:8080", roomCode: String = "", displayName: String = "User") {
        self.signalingServer = signalingServer
        self.roomCode = roomCode
        self.displayName = displayName
    }
}
