//
//  BrowserEventServer.swift
//  MyIsland
//
//  WebSocket + HTTP server on port 1996 using POSIX sockets
//  Accepts WebSocket connections for persistent bidirectional communication
//  Also serves GET /api/v1/health for diagnostics
//

import CommonCrypto
import Foundation

// MARK: - WebSocket Client

private struct WSClient {
    let fd: Int32
    let connectedAt: Date
}

// MARK: - BrowserEventServer

class BrowserEventServer {
    static let shared = BrowserEventServer()

    private var onEvent: ((BrowserEventType) -> Void)?
    private let port: UInt16 = 1996
    private var serverFd: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "app.myisland.browserEventServer", qos: .utility)

    /// Active WebSocket clients
    private var clients: [Int32: WSClient] = [:]
    private let clientsLock = NSLock()

    /// Whether any extension is connected
    var isExtensionConnected: Bool {
        clientsLock.lock()
        defer { clientsLock.unlock() }
        return !clients.isEmpty
    }

    private init() {}

    // MARK: - Public API

    func start(onEvent: @escaping (BrowserEventType) -> Void) {
        self.onEvent = onEvent

        serverFd = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            print("[BrowserEventServer] Failed to create socket")
            return
        }

        var yes: Int32 = 1
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            print("[BrowserEventServer] Failed to bind port \(port): \(String(cString: strerror(errno)))")
            close(serverFd); serverFd = -1; return
        }
        guard listen(serverFd, 10) == 0 else {
            print("[BrowserEventServer] Failed to listen: \(String(cString: strerror(errno)))")
            close(serverFd); serverFd = -1; return
        }

        let flags = fcntl(serverFd, F_GETFL)
        _ = fcntl(serverFd, F_SETFL, flags | O_NONBLOCK)

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: serverFd, queue: queue)
        acceptSource?.setEventHandler { [weak self] in self?.acceptConnection() }
        acceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.serverFd, fd >= 0 { close(fd); self?.serverFd = -1 }
        }
        acceptSource?.resume()
        print("[BrowserEventServer] Listening on ws://127.0.0.1:\(port)/ws")
    }

    func stop() {
        acceptSource?.cancel(); acceptSource = nil
        clientsLock.lock()
        for (fd, _) in clients { close(fd) }
        clients.removeAll()
        clientsLock.unlock()
        onEvent = nil
    }

    /// Send a JSON message to all connected WebSocket clients
    func broadcast(_ message: String) {
        clientsLock.lock()
        let fds = Array(clients.keys)
        clientsLock.unlock()
        for fd in fds {
            wsWriteText(fd: fd, text: message)
        }
    }

    // MARK: - Accept

    private func acceptConnection() {
        var clientAddr = sockaddr_in()
        var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(serverFd, $0, &clientLen)
            }
        }
        guard clientFd >= 0 else { return }
        queue.async { [weak self] in self?.handleNewConnection(fd: clientFd) }
    }

    // MARK: - Connection Routing

    private func handleNewConnection(fd: Int32) {
        // Set read timeout
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Read initial HTTP request
        var buffer = [UInt8](repeating: 0, count: 8192)
        let n = read(fd, &buffer, buffer.count)
        guard n > 0, let request = String(bytes: buffer[0..<n], encoding: .utf8) else {
            close(fd); return
        }

        let headers = parseHeaders(request)
        let requestLine = request.components(separatedBy: "\r\n").first ?? ""

        // Debug: log to file
        let dbg = "[\(Date())] Request: \(requestLine)\nHeaders: \(headers)\n"
        try? dbg.write(toFile: "/tmp/myisland-ws-debug.log", atomically: false, encoding: .utf8)

        // Check for WebSocket upgrade
        if headers["upgrade"]?.lowercased() == "websocket",
           let wsKey = headers["sec-websocket-key"] {
            try? "WS upgrade key=\(wsKey)\n".write(toFile: "/tmp/myisland-ws-debug.log", atomically: false, encoding: .utf8)
            handleWebSocketUpgrade(fd: fd, key: wsKey)
        }
        // Regular HTTP
        else if requestLine.hasPrefix("GET /api/v1/health") {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let connected = isExtensionConnected
            let retention = AppSettings.browserRetentionMinutes
            let heartbeat = AppSettings.browserHeartbeatSeconds
            sendHTTPResponse(fd: fd, status: 200, body: #"{"status":"ok","app":"MyIsland","version":"\#(version)","wsConnected":\#(connected),"retentionMinutes":\#(retention),"heartbeatSeconds":\#(heartbeat)}"#)
        }
        // Legacy HTTP POST (backward compat)
        else if requestLine.hasPrefix("POST /api/v1/events") {
            handleLegacyHTTPPost(fd: fd, request: request, headers: headers)
        }
        else {
            sendHTTPResponse(fd: fd, status: 404, body: #"{"error":"not found"}"#)
        }
    }

    // MARK: - WebSocket Upgrade

    private func handleWebSocketUpgrade(fd: Int32, key: String) {
        let acceptKey = computeWebSocketAccept(key: key)
        let response = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(acceptKey)",
            "", "",
        ].joined(separator: "\r\n")

        _ = response.withCString { write(fd, $0, strlen($0)) }

        // Register client
        clientsLock.lock()
        clients[fd] = WSClient(fd: fd, connectedAt: Date())
        let count = clients.count
        clientsLock.unlock()
        print("[BrowserEventServer] WebSocket connected (fd=\(fd), total=\(count))")

        // Remove read timeout for persistent connection
        var tv = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Enter frame read loop
        wsReadLoop(fd: fd)

        // Cleanup on exit
        clientsLock.lock()
        clients.removeValue(forKey: fd)
        let remaining = clients.count
        clientsLock.unlock()
        close(fd)
        print("[BrowserEventServer] WebSocket disconnected (fd=\(fd), remaining=\(remaining))")
    }

    // MARK: - WebSocket Frame Read Loop

    private func wsReadLoop(fd: Int32) {
        while true {
            // Read frame header (2 bytes minimum)
            var header = [UInt8](repeating: 0, count: 2)
            guard readExact(fd: fd, buffer: &header, count: 2) else { return }

            let fin = (header[0] & 0x80) != 0
            let opcode = header[0] & 0x0F
            let masked = (header[1] & 0x80) != 0
            var payloadLen = UInt64(header[1] & 0x7F)

            // Extended payload length
            if payloadLen == 126 {
                var ext = [UInt8](repeating: 0, count: 2)
                guard readExact(fd: fd, buffer: &ext, count: 2) else { return }
                payloadLen = UInt64(ext[0]) << 8 | UInt64(ext[1])
            } else if payloadLen == 127 {
                var ext = [UInt8](repeating: 0, count: 8)
                guard readExact(fd: fd, buffer: &ext, count: 8) else { return }
                payloadLen = 0
                for i in 0..<8 { payloadLen = (payloadLen << 8) | UInt64(ext[i]) }
            }

            // Masking key (client→server must be masked)
            var maskKey = [UInt8](repeating: 0, count: 4)
            if masked {
                guard readExact(fd: fd, buffer: &maskKey, count: 4) else { return }
            }

            // Payload
            guard payloadLen < 1_000_000 else { return } // 1MB limit
            var payload = [UInt8](repeating: 0, count: Int(payloadLen))
            if payloadLen > 0 {
                guard readExact(fd: fd, buffer: &payload, count: Int(payloadLen)) else { return }
                if masked {
                    for i in 0..<payload.count { payload[i] ^= maskKey[i % 4] }
                }
            }

            switch opcode {
            case 0x1: // Text frame
                guard fin, let text = String(bytes: payload, encoding: .utf8) else { continue }
                handleWSMessage(text, fd: fd)

            case 0x8: // Close
                // Send close frame back
                wsWriteFrame(fd: fd, opcode: 0x8, payload: Array(payload.prefix(2)))
                return

            case 0x9: // Ping → Pong
                wsWriteFrame(fd: fd, opcode: 0xA, payload: payload)

            case 0xA: // Pong (ignore)
                break

            default:
                break
            }
        }
    }

    private func handleWSMessage(_ text: String, fd: Int32) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let envelope = try JSONDecoder().decode(BrowserEventEnvelope.self, from: data)
            if let event = BrowserEventType.parse(envelope: envelope) {
                let handler = onEvent
                DispatchQueue.main.async { handler?(event) }
                // Send ACK
                wsWriteText(fd: fd, text: #"{"type":"ack","payload":{"eventType":"\#(envelope.type)"}}"#)
            }
        } catch {
            print("[BrowserEventServer] WS message parse error: \(error)")
        }
    }

    // MARK: - WebSocket Frame Write

    private func wsWriteText(fd: Int32, text: String) {
        let payload = Array(text.utf8)
        wsWriteFrame(fd: fd, opcode: 0x1, payload: payload)
    }

    private func wsWriteFrame(fd: Int32, opcode: UInt8, payload: [UInt8]) {
        var frame = [UInt8]()
        frame.append(0x80 | opcode) // FIN + opcode

        // Server→client frames are NOT masked
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count < 65536 {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(127)
            for i in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((payload.count >> i) & 0xFF))
            }
        }
        frame.append(contentsOf: payload)

        frame.withUnsafeBufferPointer { buf in
            _ = write(fd, buf.baseAddress!, buf.count)
        }
    }

    // MARK: - Legacy HTTP POST (backward compatibility)

    private func handleLegacyHTTPPost(fd: Int32, request: String, headers: [String: String]) {
        guard let bodyRange = request.range(of: "\r\n\r\n") else {
            sendHTTPResponse(fd: fd, status: 400, body: #"{"error":"no body"}"#); return
        }
        let body = String(request[bodyRange.upperBound...])

        // Read remaining body if Content-Length indicates more
        var fullBody = body
        if let clStr = headers["content-length"], let cl = Int(clStr), body.utf8.count < cl {
            let remaining = cl - body.utf8.count
            var extra = [UInt8](repeating: 0, count: remaining)
            var read = 0
            while read < remaining {
                let r = Darwin.read(fd, &extra[read], remaining - read)
                if r <= 0 { break }
                read += r
            }
            if read > 0, let extraStr = String(bytes: extra[0..<read], encoding: .utf8) {
                fullBody += extraStr
            }
        }

        guard let data = fullBody.data(using: .utf8) else {
            sendHTTPResponse(fd: fd, status: 400, body: #"{"error":"invalid body"}"#); return
        }

        do {
            let envelope = try JSONDecoder().decode(BrowserEventEnvelope.self, from: data)
            if let event = BrowserEventType.parse(envelope: envelope) {
                let handler = onEvent
                DispatchQueue.main.async { handler?(event) }
            }
            sendHTTPResponse(fd: fd, status: 200, body: #"{"ok":true}"#)
        } catch {
            sendHTTPResponse(fd: fd, status: 400, body: #"{"error":"invalid json"}"#)
        }
    }

    // MARK: - Helpers

    private func readExact(fd: Int32, buffer: inout [UInt8], count: Int) -> Bool {
        var offset = 0
        while offset < count {
            let n = read(fd, &buffer[offset], count - offset)
            if n <= 0 { return false }
            offset += n
        }
        return true
    }

    private func parseHeaders(_ request: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in request.components(separatedBy: "\r\n").dropFirst() {
            if line.isEmpty { break }
            if let colonRange = line.range(of: ":") {
                let key = line[line.startIndex..<colonRange.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        return headers
    }

    private func computeWebSocketAccept(key: String) -> String {
        let magic = key + "258EAFA5-E914-47DA-95CA-5AB9F0B63A0"
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        let data = Array(magic.utf8)
        CC_SHA1(data, CC_LONG(data.count), &digest)
        return Data(digest).base64EncodedString()
    }

    private func sendHTTPResponse(fd: Int32, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Unknown"
        }
        var resp = "HTTP/1.1 \(status) \(statusText)\r\n"
        resp += "Content-Type: application/json\r\n"
        resp += "Content-Length: \(body.utf8.count)\r\n"
        resp += "Access-Control-Allow-Origin: *\r\n"
        resp += "Connection: close\r\n\r\n"
        resp += body
        _ = resp.withCString { write(fd, $0, strlen($0)) }
        close(fd)
    }
}
