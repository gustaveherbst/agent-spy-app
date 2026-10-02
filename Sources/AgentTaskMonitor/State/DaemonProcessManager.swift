import Foundation
import AgentTaskIPC

public final class DaemonProcessManager: @unchecked Sendable {
    public static let shared = DaemonProcessManager()
    private var daemonProcess: Process?
    private let lock = NSLock()

    private init() {}

    /// Ensures agenttaskd is running. If socket is unreachable, attempts to launch it.
    public func ensureDaemonRunning(socketPath: String = IPCConstants.defaultSocketPath()) {
        lock.lock()
        defer { lock.unlock() }

        // Test if daemon is responding on socket
        let client = IPCSocketClient(socketPath: socketPath)
        do {
            try client.connect()
            client.disconnect()
            return // Daemon is already running and reachable!
        } catch {
            // Not reachable, try to spawn
        }

        // Find agenttaskd binary
        let bundleURL = Bundle.main.bundleURL
        let candidatePaths = [
            // Inside .app bundle MacOS directory
            bundleURL.appendingPathComponent("Contents/MacOS/agenttaskd").path,
            // Sibling binary in build directory
            bundleURL.deletingLastPathComponent().appendingPathComponent("agenttaskd").path,
            // Development path
            FileManager.default.currentDirectoryPath + "/.build/arm64-apple-macosx/debug/agenttaskd",
            FileManager.default.currentDirectoryPath + "/.build/debug/agenttaskd",
            "/usr/local/bin/agenttaskd"
        ]

        var execPath: String?
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                execPath = path
                break
            }
        }

        guard let binary = execPath else {
            print("agenttaskd binary not found at candidate locations, waiting for external start...")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["--socket", socketPath]
        try? proc.run()
        self.daemonProcess = proc
        print("Spawned background agenttaskd (PID \(proc.processIdentifier)) from \(binary)")
    }
}
