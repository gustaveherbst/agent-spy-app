import Foundation
import AgentTaskCore
import AgentTaskProtocol
import AgentTaskIPC
import AgentTaskProcess

public final class ClaudeAdapter: AgentAdapter, @unchecked Sendable {
    public let adapterId = "claude-code"
    public let capabilities = AdapterCapabilities(
        canDiscoverSession: true,
        canReportTaskLifecycle: true,
        canReportProgress: true,
        canReportSubtasks: true,
        canReportAttention: true,
        canDeepLink: true,
        canCancel: false
    )

    public let client: IPCSocketClient

    public init(client: IPCSocketClient = IPCSocketClient()) {
        self.client = client
    }

    /// Registers a Claude session from hook environment or process detection.
    public func registerSession(sessionId: String, projectDir: String?, pid: Int32?) async throws {
        let projectName = projectDir != nil ? (projectDir! as NSString).lastPathComponent : nil
        let proc = pid != nil ? ProcessInspector.inspect(pid: pid!) : ProcessInspector.currentProcess()

        let envelope = ATPEnvelope(
            eventType: .sessionRegistered,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "claude"),
            sessionId: sessionId,
            payload: ATPPayload(
                title: "Claude Code",
                project: ProjectInfo(name: projectName, path: projectDir),
                process: proc
            )
        )
        try await client.emitEvent(envelope)
    }

    public func endSession(sessionId: String) async throws {
        let envelope = ATPEnvelope(
            eventType: .sessionEnded,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "claude"),
            sessionId: sessionId
        )
        try await client.emitEvent(envelope)
    }
}
