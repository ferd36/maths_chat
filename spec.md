# MathsChat — P2P Text Messaging for macOS

## 1. Overview

MathsChat is a native macOS peer-to-peer chat application. Two users on separate machines can exchange text messages directly, with no central message relay server. The connection uses WebRTC data channels for P2P transport, Google's free STUN servers for NAT traversal, and a lightweight signaling mechanism to bootstrap the connection.

The name reflects the intended use: informal technical conversations where participants may discuss mathematics, code, and ideas — though the app handles any text.

### 1.1 Goals

- **Direct P2P messaging** between exactly two machines over the internet or LAN.
- **No message storage on any server.** Messages exist only on the two endpoints.
- **Native macOS experience** — SwiftUI interface, Apple Silicon optimized, system notifications.
- **Minimal infrastructure** — only a tiny signaling relay is needed; all message traffic is peer-to-peer.
- **Math-friendly input** — support for Unicode math symbols and, eventually, LaTeX rendering in-line.

### 1.2 Non-Goals (v1)

- Group chat (more than 2 participants).
- Voice or video calling.
- File transfer (beyond what fits in a text message).
- End-to-end encryption beyond what WebRTC DTLS provides by default.
- Mobile (iOS/iPadOS) builds — though the codebase will be structured to allow this later.

---

## 2. Technology Stack

| Component | Technology | Notes |
|---|---|---|
| Language | **Swift 5.9+** | Native on Apple Silicon |
| UI Framework | **SwiftUI** (macOS 14+) | Modern, declarative Mac UI |
| P2P Engine | **GoogleWebRTC** (`stasel/WebRTC-iOS` SPM package) | Provides `RTCPeerConnection`, `RTCDataChannel`, ICE, DTLS |
| STUN | Google public STUN servers | `stun:stun.l.google.com:19302`, `stun:stun1.l.google.com:19302` |
| TURN (fallback) | Optional — self-hosted `coturn` or a provider | Only needed when symmetric NAT blocks direct P2P |
| Signaling | **WebSocket** via `URLSessionWebSocketTask` | Exchanges SDP offers/answers and ICE candidates |
| Signaling Server | Minimal **Node.js** or **Python** relay | Stateless room-based relay; no message content passes through |
| Persistence | **SwiftData** or **SQLite** (local only) | Chat history stored on each machine independently |
| Notifications | **UserNotifications** framework | System banners for incoming messages when app is not focused |

### 2.1 Why WebRTC over Network.framework

Apple's `Network.framework` is excellent for local Bonjour/mDNS discovery on the same LAN, but it does not handle NAT traversal (STUN/TURN). Since the primary use case is chatting between two machines that may be on different networks (home, office, coffee shop), WebRTC's built-in ICE agent is the right tool. It handles:

- STUN binding requests to discover the public IP/port.
- ICE candidate gathering and connectivity checks.
- DTLS encryption on the data channel (automatic, no extra code).
- Fallback to TURN relay if direct P2P fails.

---

## 3. Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Machine A                          │
│                                                         │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  SwiftUI  │◄──►│  ChatEngine  │◄──►│  WebRTC      │  │
│  │   View    │    │  (ViewModel) │    │  RTCPeer     │  │
│  └──────────┘    └──────┬───────┘    │  Connection   │  │
│                         │            │  + DataChannel │  │
│                         │            └───────┬────────┘  │
│                         │                    │           │
│               ┌─────────▼──────┐             │           │
│               │  Local Store   │             │ P2P       │
│               │  (SwiftData)   │             │ (DTLS)    │
│               └────────────────┘             │           │
└──────────────────────────────────────────────┼───────────┘
                                               │
                    ┌──────────────┐            │
                    │   Signaling  │◄───────────┘ (SDP + ICE
                    │   Server     │               candidates
                    │  (WebSocket) │               only during
                    └──────┬───────┘               setup)
                           │
┌──────────────────────────┼───────────────────────────────┐
│                      Machine B                           │
│                         │                                │
│  ┌──────────────┐    ┌──▼───────────┐    ┌────────────┐ │
│  │  WebRTC      │◄──►│  ChatEngine  │◄──►│  SwiftUI   │ │
│  │  RTCPeer     │    │  (ViewModel) │    │   View     │ │
│  │  Connection  │    └──────┬───────┘    └────────────┘ │
│  │  + DataChannel│          │                           │
│  └──────────────┘  ┌───────▼────────┐                   │
│                    │  Local Store   │                    │
│                    │  (SwiftData)   │                    │
│                    └────────────────┘                    │
└──────────────────────────────────────────────────────────┘
```

### 3.1 Connection Lifecycle

1. **Both peers connect** to the signaling server via WebSocket and join a shared **room** (identified by a short room code or shared secret).
2. **Peer A creates an offer** (`RTCSessionDescription` of type `.offer`), sets it as local description, and sends it to the signaling server.
3. **Signaling server relays** the offer to Peer B.
4. **Peer B receives the offer**, sets it as remote description, creates an **answer**, sets it as local description, and sends the answer back via signaling.
5. **ICE candidates** are gathered asynchronously on both sides and relayed through the signaling server.
6. **ICE completes** — a direct P2P path (or TURN relay) is established.
7. **Data channel opens** — both peers can now send and receive text messages directly. The signaling server is no longer needed (peers may disconnect from it).

### 3.2 Reconnection

- If the P2P connection drops (network change, sleep/wake), the app automatically attempts ICE restart.
- If ICE restart fails, the app reconnects to the signaling server and performs a fresh offer/answer exchange.
- The UI shows connection state: **Connecting**, **Connected**, **Reconnecting**, **Disconnected**.

---

## 4. Data Model

### 4.1 Message

```swift
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let senderID: String          // peer identifier
    let text: String
    let timestamp: Date
    var status: DeliveryStatus     // .sending, .sent, .delivered, .failed

    enum DeliveryStatus: String, Codable {
        case sending
        case sent        // transmitted over data channel
        case delivered   // acknowledged by remote peer
        case failed
    }
}
```

### 4.2 Wire Format

Messages are sent over the RTCDataChannel as UTF-8 JSON:

```json
{
    "type": "message",
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "text": "Consider the case where ∀ε > 0, ∃δ > 0 …",
    "timestamp": "2026-02-01T14:30:00Z"
}
```

Control messages use the same channel:

```json
{ "type": "ack", "id": "550e8400-e29b-41d4-a716-446655440000" }
{ "type": "typing", "isTyping": true }
{ "type": "ping" }
```

### 4.3 Local Storage

Each machine stores its own chat history in a local SwiftData (or SQLite) database:

```
~/Library/Application Support/MathsChat/
├── chat.store           # SwiftData persistent store
└── config.json          # user preferences
```

Fields stored per message: `id`, `senderID`, `text`, `timestamp`, `status`, `roomCode`.

---

## 5. Signaling Server

The signaling server is intentionally minimal. It has **no authentication, no message storage, and no business logic** beyond room-based relay.

### 5.1 Responsibilities

- Accept WebSocket connections.
- Let clients join/leave named rooms (2 clients max per room).
- Relay any JSON message from one room member to the other.
- That's it.

### 5.2 Implementation

A single-file Node.js server using `ws`:

```
signaling_server/
├── package.json
└── server.js           # ~80 lines
```

Or a single-file Python server using `websockets`:

```
signaling_server/
└── server.py           # ~60 lines
```

### 5.3 Room Protocol

```json
// Client → Server: join a room
{ "action": "join", "room": "euler-42" }

// Server → Client: room status
{ "action": "joined", "room": "euler-42", "peers": 1 }
{ "action": "peer_joined", "room": "euler-42" }
{ "action": "peer_left", "room": "euler-42" }

// Client → Server: relay to peer
{ "action": "relay", "room": "euler-42", "payload": { ... SDP or ICE ... } }

// Server → Client: relayed from peer
{ "action": "relayed", "room": "euler-42", "payload": { ... } }
```

### 5.4 Deployment

For development/personal use, run the signaling server on one of the two machines or any reachable host:

```bash
node server.js --port 8080
```

For "real" deployment, a free-tier cloud VM (fly.io, Railway, Render) or even a Cloudflare Worker suffices — the traffic is tiny (a few KB during connection setup, then nothing).

---

## 6. UI Design

### 6.1 Main Window

```
┌───────────────────────────────────────────────────────┐
│  MathsChat                               ● Connected  │
├───────────────────────────────────────────────────────┤
│                                                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │                                                 │  │
│  │  [14:25] them:                                  │  │
│  │  Have you looked at the Riemann hypothesis      │  │
│  │  reformulation by Connes?                       │  │
│  │                                                 │  │
│  │  [14:26] me:                                    │  │
│  │  Yes — the trace formula approach. The key      │  │
│  │  insight is that ζ(s) zeros correspond to       │  │
│  │  eigenvalues of a certain operator.             │  │
│  │                                                 │  │
│  │  [14:27] them:                                  │  │
│  │  Exactly. For all s where ℜ(s) = ½ …           │  │
│  │                                                 │  │
│  │                                                 │  │
│  │                                                 │  │
│  └─────────────────────────────────────────────────┘  │
│                                                       │
│  ┌─────────────────────────────────────┐ ┌─────────┐  │
│  │ Type a message…                     │ │  Send   │  │
│  └─────────────────────────────────────┘ └─────────┘  │
│                                                       │
│  Room: euler-42          them is typing…              │
└───────────────────────────────────────────────────────┘
```

### 6.2 Connection Sheet (shown on launch or via menu)

```
┌──────────────────────────────────┐
│  Connect to a Peer               │
│                                  │
│  Signaling Server:               │
│  ┌────────────────────────────┐  │
│  │ ws://localhost:8080        │  │
│  └────────────────────────────┘  │
│                                  │
│  Room Code:                      │
│  ┌────────────────────────────┐  │
│  │ euler-42                   │  │
│  └────────────────────────────┘  │
│                                  │
│  Your Display Name:              │
│  ┌────────────────────────────┐  │
│  │ Frank                      │  │
│  └────────────────────────────┘  │
│                                  │
│         [ Connect ]              │
└──────────────────────────────────┘
```

### 6.3 Visual Style

- **Light/dark mode** — follows system appearance.
- **Message bubbles** — left-aligned (them) and right-aligned (me), with subtle background colors.
- **Monospace option** — a toggle to render message text in a monospace font (for code/math).
- **Timestamps** — shown inline, muted color.
- **Typing indicator** — "them is typing…" at the bottom when the peer is composing.
- **Connection badge** — colored dot in the title bar area: green (connected), yellow (reconnecting), red (disconnected).

### 6.4 Menu Bar

- **MathsChat > Preferences** — signaling server URL, display name, notification settings, font choice.
- **Chat > New Connection** — opens the connection sheet.
- **Chat > Disconnect** — tears down the P2P connection.
- **Chat > Clear History** — deletes local chat history for the current room.
- **Edit > Copy / Paste / Select All** — standard text editing.

---

## 7. Key Behaviors

### 7.1 Message Delivery & Acknowledgment

1. User types and presses Send (or Enter).
2. Message is written to local store with `status = .sending`.
3. Message JSON is sent over the `RTCDataChannel`.
4. Remote peer receives, stores locally, and sends back an `ack`.
5. On receiving the `ack`, local status updates to `.delivered`.
6. If no `ack` within 5 seconds, status becomes `.failed` and a retry button appears.

### 7.2 Typing Indicator

- When the user starts typing (first keystroke after idle), send `{ "type": "typing", "isTyping": true }`.
- When the user stops typing for 2 seconds, send `{ "type": "typing", "isTyping": false }`.
- The remote peer shows "them is typing…" while `isTyping` is true, with a 3-second auto-timeout.

### 7.3 Offline Queueing

- If the data channel is temporarily unavailable (e.g., during ICE restart), messages are queued locally.
- When the connection is restored, queued messages are sent in order.
- The UI shows a yellow "Reconnecting…" banner during this time.

### 7.4 Notifications

- When a message arrives and the app window is not focused, post a `UNNotificationRequest` with the message preview.
- Clicking the notification brings the app to the front.

### 7.5 Keepalive

- Send a `ping` message every 30 seconds over the data channel if no other traffic.
- If no response (or data channel error) for 10 seconds, initiate ICE restart.

---

## 8. WebRTC Integration Detail

### 8.1 Package Dependency

The standard community-maintained WebRTC binary distribution for Swift (iOS + macOS) is `stasel/WebRTC`. It compiles directly from official Google WebRTC source, supports Apple Silicon natively (`arm64`), and is available via SPM.

```swift
// Package.swift
let package = Package(
    name: "MathsChat",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC", from: "126.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MathsChat",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources"
        )
    ]
)
```

- **Repository:** `https://github.com/stasel/WebRTC`
- **Current version:** 126.0.0 (M126 WebRTC milestone)
- **Platforms:** macOS 10.11+, iOS 12+, macOS Catalyst 11.0+
- **Architectures:** arm64, x86_64 (universal)

> The key classes — `RTCPeerConnection`, `RTCDataChannel`, `RTCSessionDescription`, `RTCIceCandidate`, `RTCPeerConnectionFactory` — are the same across all WebRTC Swift distributions.

### 8.2 Core Classes

```swift
class WebRTCClient: NSObject {
    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?

    // Callbacks
    var onMessageReceived: ((String) -> Void)?
    var onConnectionStateChanged: ((RTCPeerConnectionState) -> Void)?
    var onLocalCandidate: ((RTCIceCandidate) -> Void)?
    var onLocalSDP: ((RTCSessionDescription) -> Void)?
}
```

### 8.3 ICE Configuration

```swift
let config = RTCConfiguration()
config.iceServers = [
    RTCIceServer(urlStrings: [
        "stun:stun.l.google.com:19302",
        "stun:stun1.l.google.com:19302"
    ]),
    // Optional TURN for restrictive NATs:
    // RTCIceServer(
    //     urlStrings: ["turn:my-turn-server.com:3478"],
    //     username: "user",
    //     credential: "pass"
    // )
]
config.sdpSemantics = .unifiedPlan
config.continualGatheringPolicy = .gatherContinually
```

### 8.4 Data Channel Configuration

```swift
let dcConfig = RTCDataChannelConfiguration()
dcConfig.isOrdered = true
dcConfig.isNegotiated = false
dcConfig.channelId = 0

dataChannel = peerConnection?.dataChannel(forLabel: "chat", configuration: dcConfig)
```

---

## 9. Project Structure

```
apps/maths_chat/
├── spec.md                          # this file
├── MathsChat/                       # Swift package / Xcode project
│   ├── Package.swift
│   ├── Sources/
│   │   ├── App/
│   │   │   ├── MathsChatApp.swift          # @main, WindowGroup, AppDelegate
│   │   │   └── AppState.swift              # top-level observable state
│   │   ├── Views/
│   │   │   ├── ChatView.swift              # message list + input field
│   │   │   ├── MessageBubble.swift         # single message row
│   │   │   ├── ConnectionSheet.swift       # server URL + room code form
│   │   │   ├── StatusBadge.swift           # connection state indicator
│   │   │   └── TypingIndicator.swift       # animated "typing…"
│   │   ├── Networking/
│   │   │   ├── WebRTCClient.swift          # RTCPeerConnection wrapper
│   │   │   ├── SignalingClient.swift        # WebSocket to signaling server
│   │   │   └── SignalingMessage.swift       # Codable types for signaling
│   │   ├── Models/
│   │   │   ├── ChatMessage.swift           # message data model
│   │   │   └── ConnectionConfig.swift      # signaling URL, room, name
│   │   ├── Services/
│   │   │   ├── ChatEngine.swift            # orchestrates signaling + WebRTC + UI
│   │   │   ├── MessageStore.swift          # local persistence (SwiftData)
│   │   │   └── NotificationService.swift   # UNUserNotificationCenter
│   │   └── Utilities/
│   │       └── DateFormatting.swift
│   └── Tests/
│       └── ...
├── signaling_server/
│   ├── server.py                    # Python signaling relay (~60 lines)
│   └── requirements.txt             # websockets
└── build_app.sh                     # builds .app bundle
```

---

## 10. Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Enter` | Send message |
| `Shift+Enter` | New line in message |
| `Cmd+K` | Clear chat history |
| `Cmd+N` | New connection (open connection sheet) |
| `Cmd+W` | Close window / disconnect |
| `Cmd+,` | Preferences |
| `Cmd+D` | Disconnect from peer |
| `Cmd+Shift+M` | Toggle monospace font |

---

## 11. Configuration

### 11.1 `config.json`

```json
{
    "signaling_server": "ws://localhost:8080",
    "display_name": "Frank",
    "last_room": "euler-42",
    "font": {
        "family": "Menlo",
        "size": 14,
        "monospace_mode": false
    },
    "notifications_enabled": true,
    "auto_reconnect": true
}
```

---

## 12. Security Considerations

- **DTLS encryption** is automatic on WebRTC data channels — all P2P traffic is encrypted in transit.
- **No messages on the server** — the signaling server only relays SDP and ICE candidates, never chat content.
- **Room codes** serve as lightweight access control. For stronger security, a shared secret can be used to HMAC-sign signaling messages (v2 feature).
- **Local storage** is not encrypted by default (relies on macOS FileVault). A future version could use the Keychain for sensitive config.

---

## 13. Implementation Phases

### Phase 1 — Signaling + P2P Connection (no UI)

- [ ] Write the signaling server (Python `websockets`).
- [ ] Implement `SignalingClient` (Swift WebSocket wrapper).
- [ ] Implement `WebRTCClient` (peer connection + data channel).
- [ ] Test: two Terminal processes can exchange text via data channel.

### Phase 2 — Basic Chat UI

- [ ] `ChatView` with message list and input field.
- [ ] `ConnectionSheet` for entering server URL, room, and name.
- [ ] Wire `ChatEngine` to connect signaling → WebRTC → UI.
- [ ] Message send/receive with delivery status.

### Phase 3 — Polish

- [ ] Local persistence (SwiftData).
- [ ] Typing indicator.
- [ ] System notifications.
- [ ] Reconnection logic (ICE restart, signaling reconnect).
- [ ] Keepalive pings.
- [ ] Preferences window.

### Phase 4 — Extras

- [ ] LaTeX rendering in message bubbles (using MathJax/KaTeX via WKWebView or a native renderer).
- [ ] Monospace toggle.
- [ ] Message search.
- [ ] Export chat to `.txt`.

---

## 14. Build & Run

### Signaling server

```bash
cd apps/maths_chat/signaling_server
pip install websockets
python server.py --port 8080
```

### macOS app

```bash
cd apps/maths_chat/MathsChat
swift build
swift run
# or: open MathsChat.xcodeproj in Xcode
```

### Standalone `.app` bundle

```bash
bash build_app.sh
open MathsChat.app
```

---

## 15. Entitlements

The app requires these macOS entitlements (in `MathsChat.entitlements`):

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

These allow outgoing connections (to the signaling server and STUN) and incoming connections (for the P2P data channel).
