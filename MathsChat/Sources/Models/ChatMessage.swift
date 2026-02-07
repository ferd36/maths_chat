import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let senderID: String          // "me" or peer identifier
    let text: String
    let timestamp: Date
    var status: DeliveryStatus

    enum DeliveryStatus: String, Codable {
        case sending
        case sent        // transmitted over data channel
        case delivered   // acknowledged by remote peer
        case failed
    }

    init(id: UUID = UUID(), senderID: String, text: String, timestamp: Date = Date(), status: DeliveryStatus = .sending) {
        self.id = id
        self.senderID = senderID
        self.text = text
        self.timestamp = timestamp
        self.status = status
    }

    mutating func updateStatus(_ newStatus: DeliveryStatus) {
        self.status = newStatus
    }
}

// Wire format for data channel
struct WireMessage: Codable {
    let type: String
    let id: String?
    let text: String?
    let timestamp: String?
    let isTyping: Bool?

    init(type: String, id: String? = nil, text: String? = nil, timestamp: String? = nil, isTyping: Bool? = nil) {
        self.type = type
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isTyping = isTyping
    }
}
