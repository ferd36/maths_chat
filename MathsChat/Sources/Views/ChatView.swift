import SwiftUI

struct ChatView: View {
    @ObservedObject var engine: ChatEngine
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                statusBadge
                Spacer()
                if engine.isTyping {
                    Text("Peer is typing…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(engine.messages) { message in
                            MessageBubble(message: message, isMe: message.senderID == "me")
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: engine.messages.count) {
                    if let last = engine.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 8) {
                TextField("Type a message…", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .focused($isInputFocused)
                    .onChange(of: messageText) {
                        if !messageText.isEmpty {
                            engine.userDidType()
                        }
                    }
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(messageText.isEmpty || engine.connectionState != .connected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        switch engine.connectionState {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .yellow
        case .disconnected:
            return .red
        }
    }

    private var statusText: String {
        switch engine.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting…"
        case .reconnecting:
            return "Reconnecting…"
        case .disconnected:
            return "Disconnected"
        }
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        engine.sendMessage(messageText)
        messageText = ""
    }
}
