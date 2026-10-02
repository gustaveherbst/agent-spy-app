import Foundation
import Darwin
import AgentTaskCore
import AgentTaskProtocol
import AgentTaskIPC
import AgentTaskProcess

public final class ProcessDiscoveryAdapter: AgentAdapter, @unchecked Sendable {
    public let adapterId = "process-discovery"
    public let capabilities = AdapterCapabilities(
        canDiscoverSession: true,
        canReportTaskLifecycle: false,
        canReportProgress: false,
        canReportSubtasks: false,
        canReportAttention: false,
        canDeepLink: false,
        canCancel: false
    )

    public let client: IPCSocketClient
    private static let knownAgentBinaries: [String: String] = [
        "claude": "claude",
        "antigravity": "antigravity",
        "codex": "codex",
        "auggie": "auggie",
        "opencode": "opencode",
        "levax": "levax"
    ]

    public init(client: IPCSocketClient = IPCSocketClient()) {
        self.client = client
    }

    /// Scans running processes and returns any discovered agent processes.
    public func scanRunningAgents() -> [(agent: String, process: ProcessIdentity)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0

        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 && size > 0 else {
            return []
        }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)

        guard sysctl(&mib, 4, &procList, &size, nil, 0) == 0 else {
            return []
        }

        var results: [(agent: String, process: ProcessIdentity)] = []
        let actualCount = size / MemoryLayout<kinfo_proc>.stride

        for i in 0..<actualCount {
            let pid = procList[i].kp_proc.p_pid
            if pid <= 0 { continue }

            var pathBuffer = [CChar](repeating: 0, count: 4096)
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard pathLength > 0 else { continue }
            let execPath = String(cString: pathBuffer)
            let binaryName = (execPath as NSString).lastPathComponent.lowercased()

            for (knownName, agent) in Self.knownAgentBinaries {
                if binaryName == knownName || binaryName.contains(knownName) {
                    if let identity = ProcessInspector.inspect(pid: pid) {
                        results.append((agent: agent, process: identity))
                    }
                    break
                }
            }
        }

        return results
    }
}
