import Foundation

/// Identity of an OS process bound to an agent task.
public struct ProcessIdentity: Codable, Sendable, Equatable {
    public var pid: Int32
    public var ppid: Int32?
    public var processStartedAt: Date?
    public var executable: String?
    public var bundleId: String?
    public var cwd: String?
    public var lastAliveAt: Date?

    public init(
        pid: Int32,
        ppid: Int32? = nil,
        processStartedAt: Date? = nil,
        executable: String? = nil,
        bundleId: String? = nil,
        cwd: String? = nil,
        lastAliveAt: Date? = nil
    ) {
        self.pid = pid
        self.ppid = ppid
        self.processStartedAt = processStartedAt
        self.executable = executable
        self.bundleId = bundleId
        self.cwd = cwd
        self.lastAliveAt = lastAliveAt
    }
}
