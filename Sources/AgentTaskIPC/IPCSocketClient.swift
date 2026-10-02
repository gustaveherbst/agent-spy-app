import Foundation
import Darwin
import AgentTaskCore
import AgentTaskProtocol

public enum IPCClientError: Error, CustomStringConvertible, Sendable {
    case notConnected
    case connectionFailed(String)
    case timeout
    case serverError(String)
    case malformedResponse

    public var description: String {
        switch self {
        case .notConnected: return "Not connected to agenttaskd socket"
        case .connectionFailed(let m): return "Connection to daemon failed: \(m)"
        case .timeout: return "Request timed out"
        case .serverError(let m): return "Server error: \(m)"
        case .malformedResponse: return "Malformed server response"
        }
    }
}

public final class IPCSocketClient: @unchecked Sendable {
    public let socketPath: String
    private var clientFd: Int32 = -1
    private let lock = NSLock()
    private var isConnected = false
    private var pendingRequests: [String: CheckedContinuation<IPCServerMessage, Error>] = [:]
    private var streamContinuations: [UUID: AsyncStream<IPCServerMessage>.Continuation] = [:]
    private var readBuffer = Data()
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.agenttask.ipc.client", qos: .userInitiated)

    public init(socketPath: String = IPCConstants.defaultSocketPath()) {
        self.socketPath = socketPath
    }

    deinit {
        disconnect()
    }

    public var connected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isConnected
    }

    public func connect() throws {
        lock.lock()
        defer { lock.unlock() }

        if isConnected { return }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCClientError.connectionFailed("Failed to create socket")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count < maxLen else {
            close(fd)
            throw IPCClientError.connectionFailed("Socket path too long")
        }

        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress!, buf.count)
            }
        }

        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectRes == 0 else {
            let err = errno
            close(fd)
            throw IPCClientError.connectionFailed(String(cString: strerror(err)))
        }

        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        self.clientFd = fd
        self.isConnected = true
        self.readBuffer = Data()

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleRead()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.readSource = source
    }

    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        guard isConnected else { return }
        isConnected = false

        readSource?.cancel()
        readSource = nil

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: IPCClientError.notConnected)
        }
        pendingRequests.removeAll()

        for (_, cont) in streamContinuations {
            cont.finish()
        }
        streamContinuations.removeAll()
    }

    private func handleRead() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientFd, &buffer, buffer.count)

        if bytesRead <= 0 {
            disconnect()
            return
        }

        lock.lock()
        readBuffer.append(buffer, count: bytesRead)

        var lines: [String] = []
        while let newlineIndex = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = readBuffer.subdata(in: 0..<newlineIndex)
            readBuffer.removeSubrange(0...newlineIndex)
            if let lineStr = String(data: lineData, encoding: .utf8), !lineStr.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(lineStr)
            }
        }
        lock.unlock()

        for line in lines {
            processIncomingLine(line)
        }
    }

    private func processIncomingLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            let msg = try JSONDecoder().decode(IPCServerMessage.self, from: data)

            // 1. Check if it's a response to a pending request
            if let replyTo = msg.replyTo {
                lock.lock()
                let cont = pendingRequests.removeValue(forKey: replyTo)
                lock.unlock()
                if let cont = cont {
                    if msg.status == "error" {
                        cont.resume(throwing: IPCClientError.serverError(msg.error ?? "Unknown error"))
                    } else {
                        cont.resume(returning: msg)
                    }
                    if msg.type != "snapshot" && msg.type != "task_update" {
                        return
                    }
                }
            }

            // 2. Broadcast to stream subscribers
            lock.lock()
            let continuations = Array(streamContinuations.values)
            lock.unlock()
            for cont in continuations {
                cont.yield(msg)
            }
        } catch {
            // Decoding error
        }
    }

    public func send(request: IPCClientRequest) async throws -> IPCServerMessage {
        if !connected {
            try connect()
        }

        let data = try JSONEncoder().encode(request)
        var packet = data
        packet.append(contentsOf: [UInt8(ascii: "\n")])

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pendingRequests[request.id] = continuation
            lock.unlock()

            let writeRes = packet.withUnsafeBytes { ptr in
                write(clientFd, ptr.baseAddress, ptr.count)
            }

            if writeRes < 0 {
                lock.lock()
                pendingRequests.removeValue(forKey: request.id)
                lock.unlock()
                continuation.resume(throwing: IPCClientError.connectionFailed("Failed to write to socket"))
            }
        }
    }

    /// Subscribes to live server messages (snapshots, task updates, event broadcasts).
    public func subscribe() -> AsyncStream<IPCServerMessage> {
        let streamId = UUID()
        return AsyncStream(IPCServerMessage.self) { continuation in
            lock.lock()
            streamContinuations[streamId] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] (_: AsyncStream<IPCServerMessage>.Continuation.Termination) in
                self?.lock.lock()
                self?.streamContinuations.removeValue(forKey: streamId)
                self?.lock.unlock()
            }

            // Send subscription request
            _Concurrency.Task {
                do {
                    _ = try await self.send(request: IPCClientRequest(type: "subscribe"))
                } catch {
                    // Ignore if already subscribed or connection drops
                }
            }
        }
    }

    /// Emits an ATP event to the daemon.
    public func emitEvent(_ event: ATPEnvelope) async throws {
        let req = IPCClientRequest(type: "emit_event", event: event)
        let resp = try await send(request: req)
        if resp.status == "error" {
            throw IPCClientError.serverError(resp.error ?? "Failed to emit event")
        }
    }

    /// Fetches a current state snapshot.
    public func getSnapshot() async throws -> TaskSnapshot {
        let req = IPCClientRequest(type: "get_snapshot")
        let resp = try await send(request: req)
        guard let snap = resp.snapshot else {
            throw IPCClientError.malformedResponse
        }
        return snap
    }
}
