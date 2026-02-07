import SwiftUI

struct ConnectionSheet: View {
    @Binding var isPresented: Bool
    @State private var signalingServer = "ws://localhost:8080"
    @State private var roomCode = ""
    @State private var displayName = "User"
    @State private var isInitiator = true
    @State private var isConnecting = false

    let onConnect: (ConnectionConfig, Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Connect to a Peer")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Signaling Server:") {
                    TextField("ws://localhost:8080", text: $signalingServer)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Room Code:") {
                    TextField("euler-42", text: $roomCode)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Your Display Name:") {
                    TextField("User", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("I will initiate the connection", isOn: $isInitiator)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Connect") {
                    connect()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting || signalingServer.isEmpty || roomCode.isEmpty || displayName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func connect() {
        isConnecting = true
        let config = ConnectionConfig(
            signalingServer: signalingServer,
            roomCode: roomCode,
            displayName: displayName
        )
        onConnect(config, isInitiator)
        isConnecting = false
    }
}
