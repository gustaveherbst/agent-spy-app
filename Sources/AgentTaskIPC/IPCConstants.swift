import Foundation

public enum IPCConstants {
    /// Resolves the socket path, respecting AGENTTASK_SOCKET_PATH if set.
    public static func defaultSocketPath() -> String {
        if let env = ProcessInfo.processInfo.environment["AGENTTASK_SOCKET_PATH"], !env.isEmpty {
            return env
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AgentTask", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("agenttask.sock").path
    }

    public static let maxMessageSize = 1024 * 1024 // 1 MB
}
