<p align="center">
  <a href="../README.md">Home</a> &nbsp;&bull;&nbsp;
  <a href="GettingStarted.md">Getting Started</a> &nbsp;&bull;&nbsp;
  <a href="Interceptors.md">Interceptors</a> &nbsp;&bull;&nbsp;
  <b>WebSocket</b> &nbsp;&bull;&nbsp;
  <a href="Validation.md">Validation</a> &nbsp;&bull;&nbsp;
  <a href="Caching.md">Caching</a> &nbsp;&bull;&nbsp;
  <a href="Testing.md">Testing</a> &nbsp;&bull;&nbsp;
  <a href="Advanced.md">Advanced</a>
</p>

---

# WebSocket

Fiber's WebSocket module provides a protocol-based abstraction over URLSession WebSocket with typed messages, async streams, and automatic reconnection strategies.

```swift
import FiberWebSocket
```

## Table of Contents

- [Connecting](#connecting)
- [Sending Messages](#sending-messages)
- [Receiving Events](#receiving-events)
- [Typed Messages](#typed-messages)
- [Auto-Reconnection](#auto-reconnection)
- [Connection Lifecycle](#connection-lifecycle)
- [Testing WebSockets](#testing-websockets)

---

## Connecting

```swift
let ws = URLSessionWebSocketTransport.connect(
    to: URL(string: "wss://ws.example.com/chat")!
)
```

With custom headers and subprotocols:

```swift
let ws = URLSessionWebSocketTransport.connect(
    to: URL(string: "wss://ws.example.com/chat")!,
    headers: [
        "Authorization": "Bearer my-token",
        "X-Client-ID": "ios-app"
    ],
    protocols: ["chat.v2"],
    configuration: {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return config
    }()
)
```

---

## Sending Messages

```swift
// Plain text
try await ws.send("Hello, server!")

// Binary data
try await ws.send(imageData)

// JSON-encoded
try await ws.sendJSON(ChatMessage(user: "alice", text: "hello"))

// WebSocketMessage enum directly
try await ws.send(.text("ping"))
try await ws.send(.binary(binaryData))
try await ws.send(.json(myEncodable))
```

---

## Receiving Events

Use the `events` AsyncStream to handle all WebSocket lifecycle events:

```swift
for await event in ws.events {
    switch event {
    case .connected:
        print("Connected!")
        try await ws.send("Hello")

    case .message(.text(let text)):
        print("Text: \(text)")

    case .message(.binary(let data)):
        print("Binary: \(data.count) bytes")

    case .disconnected(let code, let reason):
        print("Disconnected: code=\(code ?? 0) reason=\(reason ?? "")")

    case .error(let error):
        print("Error: \(error)")
    }
}
```

### Messages-Only Stream

If you only care about messages (not lifecycle events):

```swift
for await message in ws.messages {
    switch message {
    case .text(let text):
        print(text)
    case .binary(let data):
        process(data)
    }
}
```

---

## Typed Messages

### Sending JSON

```swift
struct ChatMessage: Codable {
    let user: String
    let text: String
    let timestamp: Date
}

// Convenience method on the WebSocket
try await ws.sendJSON(ChatMessage(
    user: "alice",
    text: "hello everyone",
    timestamp: Date()
))

// Or create a message explicitly
let msg = try WebSocketMessage.json(ChatMessage(...))
try await ws.send(msg)
```

### Decoding Received Messages

```swift
for await message in ws.messages {
    if let chat: ChatMessage = try? message.decode() {
        print("\(chat.user): \(chat.text)")
    }
}
```

### Message Properties

```swift
let msg = WebSocketMessage.text("hello")
msg.text   // "hello"
msg.data   // Data("hello".utf8)

let msg = WebSocketMessage.binary(myData)
msg.text   // nil
msg.data   // myData
```

---

## Auto-Reconnection

`ReconnectingWebSocket` wraps any `FiberWebSocketProtocol` implementation with automatic reconnection on disconnection or error.

```swift
let ws = ReconnectingWebSocket(
    connect: {
        URLSessionWebSocketTransport.connect(
            to: URL(string: "wss://ws.example.com/chat")!,
            headers: ["Authorization": "Bearer \(currentToken)"]
        )
    },
    strategy: .exponentialBackoff(
        baseDelay: 1.0,        // start at 1s
        maxDelay: 30.0,        // cap at 30s
        maxAttempts: 10         // give up after 10 attempts
    ),
    logger: OSLogFiberLogger(subsystem: "com.myapp.ws")
)

// Start the connection
Task { await ws.start() }

// Use normally — reconnection is transparent
for await event in ws.events {
    switch event {
    case .connected:
        print("Connected (or reconnected)")
    case .message(let msg):
        handle(msg)
    case .disconnected:
        print("Disconnected — will auto-reconnect")
    case .error(let error):
        print("Error: \(error) — will auto-reconnect")
    }
}

// Send messages (queued if reconnecting)
try await ws.send(.text("hello"))

// Stop reconnection and close
ws.stop()
```

### Built-in Reconnection Strategies

| Strategy | Behavior | Example Delays |
|----------|----------|----------------|
| `.exponentialBackoff()` | Doubles each time with jitter | 1s, 2s, 4s, 8s, 16s... |
| `.fixedDelay(5.0)` | Same delay every time | 5s, 5s, 5s, 5s... |
| `.linearBackoff()` | Increases by a fixed amount | 1s, 2s, 3s, 4s, 5s... |
| `.none` | No reconnection | — |

### Custom Strategies

```swift
let custom = ReconnectionStrategy(
    maxAttempts: 5,
    delayForAttempt: { attempt in
        // Custom: fast first retry, then slow
        attempt == 0 ? 0.1 : Double(attempt) * 2.0
    }
)

let ws = ReconnectingWebSocket(
    connect: { /* ... */ },
    strategy: custom
)
```

---

## Connection Lifecycle

### States

```swift
ws.state  // .connecting, .connected, .disconnecting, .disconnected
```

### Closing

```swift
// Graceful close with default code (1000)
ws.close()

// With specific close code and reason
ws.close(code: 1001, reason: "Going away")
```

---

## Testing WebSockets

`FiberTesting` provides `MockWebSocket` for testing WebSocket-based code without real connections.

```swift
import FiberTesting

// Create a paired mock — messages sent to one appear on the other
let (client, server) = MockWebSocket.pair()

// Simulate server sending a message
try await server.send(.text("welcome"))

// Client receives it
for await event in client.events {
    if case .message(.text(let text)) = event {
        #expect(text == "welcome")
        break
    }
}

// Test client sending
try await client.send(.text("hello"))
for await event in server.events {
    if case .message(.text(let text)) = event {
        #expect(text == "hello")
        break
    }
}

// Test disconnection
client.close(code: 1000, reason: "test done")
#expect(client.state == .disconnected)
#expect(server.state == .disconnected)
```

For more testing patterns, see the [Testing guide](Testing.md).

---

## Real-World Example: Chat Room

Pure functions for message handling, composed with a ReconnectingWebSocket.

```swift
import FiberWebSocket

struct ChatMessage: Codable, Sendable {
    let user: String
    let text: String
    let timestamp: Date
}

struct JoinMessage: Codable, Sendable {
    let type: String
}

// MARK: - Pure function: parse incoming WebSocket events into chat messages

func parseChatMessage(_ event: WebSocketEvent) -> ChatMessage? {
    guard case .message(let msg) = event else { return nil }
    return try? msg.decode(ChatMessage.self)
}

// MARK: - Factory: create a chat WebSocket for a given room

func makeChatSocket(roomID: String, token: String) -> ReconnectingWebSocket {
    ReconnectingWebSocket(
        connect: {
            URLSessionWebSocketTransport.connect(
                to: URL(string: "wss://chat.example.com/rooms/\(roomID)")!,
                headers: ["Authorization": "Bearer \(token)"]
            )
        },
        strategy: .exponentialBackoff(maxAttempts: 20),
        logger: PrintFiberLogger(minLevel: .info)
    )
}

// MARK: - Usage: compose everything

func runChat(roomID: String, token: String, user: String) async throws {
    let ws = makeChatSocket(roomID: roomID, token: token)
    Task { await ws.start() }

    for await event in ws.events {
        switch event {
        case .connected:
            try await ws.send(.json(JoinMessage(type: "join")))

        case .message:
            if let chat = parseChatMessage(event) {
                print("[\(chat.user)] \(chat.text)")
            }

        case .disconnected, .error:
            break  // ReconnectingWebSocket handles reconnection
        }
    }
}

// Send a message — just a function call on the socket value
func sendChat(_ text: String, as user: String, via ws: ReconnectingWebSocket) async throws {
    try await ws.send(.json(ChatMessage(user: user, text: text, timestamp: Date())))
}
```

---

<p align="center">
  <a href="Interceptors.md">&larr; Interceptors</a> &nbsp;&bull;&nbsp;
  <a href="Validation.md">Validation &rarr;</a>
</p>
