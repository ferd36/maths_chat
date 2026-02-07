import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    let isMe: Bool

    var body: some View {
        HStack {
            if isMe {
                Spacer()
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMe ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .cornerRadius(12)

                HStack(spacing: 4) {
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if isMe {
                        statusIcon
                    }
                }
            }
            .frame(maxWidth: 400, alignment: isMe ? .trailing : .leading)

            if !isMe {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var statusIcon: some View {
        Group {
            switch message.status {
            case .sending:
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            case .sent:
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            case .delivered:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.blue)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
