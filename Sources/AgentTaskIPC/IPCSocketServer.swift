import Foundation
import Darwin
import AgentTaskCore
import AgentTaskProtocol

public final class IPCSocketServer: @unchecked Sendable {
    public let socketPath: String
    private var serverFd: Int32 = -1
    private var isRunning = false
    private let lock = NSLock()
    private var clientBuffers: [Int32: Data] = [:]
    private var subscribedClients = Set<Int32>()
    private var clientSources: [Int32: DispatchSourceRead] = [:]
    private var listenSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.agenttask.ipc.server", attributes: .concurrent)

    public var onRequest: (@Sendable (IPCClientRequest, Int32) -> Void)?

    public init(socketPath: String = IPCConstants.defaultSocketPath()) {
        self.socketPath = socketPath
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }

        // Remove existing socket if any
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count < maxLen else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }

        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress!, buf.count)
            }
        }

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindRes == 0 else {
            let err = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EADDRINUSE)
        }

        // Enforce owner-only permissions (0600)
        chmod(socketPath, S_IRUSR | S_IWUSR)

        // Set serverFd non-blocking
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        guard listen(fd, 64) == 0 else {
            let err = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
        }

        self.serverFd = fd
        self.isRunning = true

        // Accept source
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnections()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.listenSource = source
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard isRunning else { return }
        isRunning = false

        listenSource?.cancel()
        listenSource = nil

        for (_, src) in clientSources {
            src.cancel()
        }
        clientSources.removeAll()
        clientBuffers.removeAll()
        subscribedClients.removeAll()

        unlink(socketPath)
    }

    private func acceptConnections() {
        while true {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(serverFd, sa, &clientAddrLen)
                }
            }

            guard clientFd >= 0 else {
                break // No more incoming connections to accept
            }

            // Set non-blocking
            let flags = fcntl(clientFd, F_GETFL, 0)
            _ = fcntl(clientFd, F_SETFL, flags | O_NONBLOCK)

            // Prevent SIGPIPE
            var nosigpipe: Int32 = 1
            setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

            lock.lock()
            clientBuffers[clientFd] = Data()

            let clientSource = DispatchSource.makeReadSource(fileDescriptor: clientFd, queue: queue)
            clientSource.setEventHandler { [weak self] in
                self?.readClient(fd: clientFd)
            }
            clientSource.setCancelHandler {
                close(clientFd)
            }
            clientSource.resume()
            clientSources[clientFd] = clientSource
            lock.unlock()
        }
    }

    private func readClient(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count)

        if bytesRead <= 0 {
            // Client disconnected or error
            removeClient(fd: fd)
            return
        }

        lock.lock()
        guard var clientData = clientBuffers[fd] else {
            lock.unlock()
            return
        }
        clientData.append(buffer, count: bytesRead)

        // Process line by line
        var lines: [String] = []
        while let newlineIndex = clientData.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = clientData.subdata(in: 0..<newlineIndex)
            clientData.removeSubrange(0...newlineIndex)
            if let lineStr = String(data: lineData, encoding: .utf8), !lineStr.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(lineStr)
            }
        }
        clientBuffers[fd] = clientData
        lock.unlock()

        for line in lines {
            processLine(line, from: fd)
        }
    }

    private func processLine(_ line: String, from fd: Int32) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            let request = try JSONDecoder().decode(IPCClientRequest.self, from: data)
            if request.type == "subscribe" {
                lock.lock()
                subscribedClients.insert(fd)
                lock.unlock()
            }
            onRequest?(request, fd)
        } catch {
            let errResponse = IPCServerMessage.failure(replyTo: "unknown", error: "Malformed request: \(error.localizedDescription)")
            send(errResponse, to: fd)
        }
    }

    public func send(_ message: IPCServerMessage, to fd: Int32) {
        do {
            let data = try JSONEncoder().encode(message)
            var packet = data
            packet.append(contentsOf: [UInt8(ascii: "\n")])
            _ = packet.withUnsafeBytes { ptr in
                write(fd, ptr.baseAddress, ptr.count)
            }
        } catch {
            // Encode error
        }
    }

    public func broadcast(_ message: IPCServerMessage) {
        lock.lock()
        let clients = Array(subscribedClients)
        lock.unlock()

        for fd in clients {
            send(message, to: fd)
        }
    }

    private func removeClient(fd: Int32) {
        lock.lock()
        defer { lock.unlock() }

        if let src = clientSources.removeValue(forKey: fd) {
            src.cancel()
        }
        clientBuffers.removeValue(forKey: fd)
        subscribedClients.remove(fd)
    }
}
