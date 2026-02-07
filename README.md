# MathsChat — P2P Text Messaging for macOS

A native macOS peer-to-peer chat application built with Swift, SwiftUI, and WebRTC.

## Quick Start

### 1. Start the Signaling Server

The signaling server is a minimal Python WebSocket relay. It only forwards connection setup messages (SDP offers/answers and ICE candidates) — **no chat messages ever pass through it**.

```bash
cd signaling_server
pip install -r requirements.txt
python server.py --port 8080
```

The server will listen on `ws://localhost:8080` by default.

### 2. Build and Run the macOS App

```bash
cd MathsChat
swift build
swift run
```

Or build a standalone `.app` bundle:

```bash
cd .
bash build_app.sh
open MathsChat.app
```

### 3. Connect Two Peers

1. **Run the app on two Macs** (or two instances on the same Mac for testing).
2. **On the first Mac**: Enter the signaling server URL (e.g., `ws://localhost:8080` or `ws://YOUR_SERVER_IP:8080`), choose a room code (e.g., `euler-42`), enter your display name, and check "I will initiate the connection". Click **Connect**.
3. **On the second Mac**: Enter the same signaling server URL and room code, enter your display name, and **uncheck** "I will initiate the connection". Click **Connect**.
4. Wait a few seconds for the WebRTC connection to establish (you'll see "Connected" in green).
5. Start chatting! Messages are sent directly peer-to-peer with DTLS encryption.

## Architecture

- **Signaling Server** (`signaling_server/server.py`): Minimal Python WebSocket relay for connection setup only.
- **WebRTC Client** (`Sources/Networking/WebRTCClient.swift`): Handles RTCPeerConnection, RTCDataChannel, ICE, and DTLS.
- **Signaling Client** (`Sources/Networking/SignalingClient.swift`): WebSocket client for exchanging SDP and ICE candidates.
- **Chat Engine** (`Sources/Services/ChatEngine.swift`): Orchestrates signaling + WebRTC + message handling.
- **SwiftUI Views** (`Sources/Views/`): Native macOS chat interface.

## Project Structure

```
maths_chat/
├── spec.md                    # Full specification
├── README.md                  # This file
├── build_app.sh               # Build script for .app bundle
├── signaling_server/
│   ├── server.py              # Python WebSocket signaling server
│   └── requirements.txt        # Python dependencies
└── MathsChat/                 # Swift package
    ├── Package.swift
    └── Sources/
        ├── App/               # App entry point
        ├── Views/             # SwiftUI views
        ├── Networking/        # WebRTC + Signaling clients
        ├── Models/            # Data models
        └── Services/          # Chat engine
```

## Dependencies

- **Swift 5.9+**
- **macOS 14+**
- **WebRTC** (via `stasel/WebRTC` SPM package, v126.0.0)
- **Python 3.8+** (for signaling server)
- **websockets** Python package

## Notes

- The first build may take several minutes as it downloads and compiles the WebRTC framework (~100MB).
- For testing on the same machine, run two instances of the app.
- For internet P2P, ensure the signaling server is reachable from both machines (or use a cloud VM).
- Messages are encrypted in transit via WebRTC's built-in DTLS.
- Chat history is stored locally on each machine (not yet implemented in this prototype).

## Troubleshooting

- **"Room is full"**: Only 2 peers per room. Make sure you're not trying to connect a third client.
- **Connection fails**: Check that the signaling server is running and reachable. Check firewall settings.
- **Build errors**: Ensure you have Xcode Command Line Tools installed (`xcode-select --install`).
