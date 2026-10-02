import Foundation
import AgentTaskCore
import AgentTaskProtocol
import AgentTaskIPC
import AgentTaskProcess

public final class CLIAdapter: AgentAdapter, @unchecked Sendable {
    public let adapterId = "cli"
    public let capabilities = AdapterCapabilities(
        canDiscoverSession: true,
        canReportTaskLifecycle: true,
        canReportProgress: true,
        canReportSubtasks: true,
        canReportAttention: true,
        canDeepLink: false,
        canCancel: true
    )

    public let client: IPCSocketClient

    public init(client: IPCSocketClient = IPCSocketClient()) {
        self.client = client
    }

    public func startSession(agent: String, project: String?, title: String?) async throws -> String {
        let sessionId = ATPIdentifiers.newSessionId()
        let projectName = project != nil ? (project! as NSString).lastPathComponent : nil

        let envelope = ATPEnvelope(
            eventType: .sessionRegistered,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: agent),
            sessionId: sessionId,
            payload: ATPPayload(
                title: title ?? "CLI Session",
                project: ProjectInfo(name: projectName, path: project)
            )
        )

        try await client.emitEvent(envelope)
        return sessionId
    }

    public func endSession(sessionId: String) async throws {
        let envelope = ATPEnvelope(
            eventType: .sessionEnded,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "cli"),
            sessionId: sessionId
        )
        try await client.emitEvent(envelope)
    }

    public func startTask(
        title: String,
        sessionId: String,
        parentTaskId: String? = nil,
        detail: String? = nil,
        project: String? = nil,
        pid: Int32? = nil
    ) async throws -> String {
        let taskId = ATPIdentifiers.newTaskId()
        let proc: ProcessIdentity?
        if let explicitPid = pid {
            proc = ProcessInspector.inspect(pid: explicitPid) ?? ProcessIdentity(pid: explicitPid, processStartedAt: Date())
        } else {
            proc = nil
        }

        let projectName = project != nil ? (project! as NSString).lastPathComponent : nil

        let envelope = ATPEnvelope(
            eventType: .taskStarted,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "cli"),
            sessionId: sessionId,
            taskId: taskId,
            parentTaskId: parentTaskId,
            payload: ATPPayload(
                title: title,
                detail: detail,
                project: ProjectInfo(name: projectName, path: project),
                process: proc
            )
        )

        try await client.emitEvent(envelope)
        return taskId
    }

    public func reportProgress(
        taskId: String,
        sessionId: String,
        fraction: Double? = nil,
        completed: Double? = nil,
        total: Double? = nil,
        message: String? = nil
    ) async throws {
        let envelope = ATPEnvelope(
            eventType: .taskProgress,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "cli"),
            sessionId: sessionId,
            taskId: taskId,
            payload: ATPPayload(
                fraction: fraction,
                completedUnits: completed,
                totalUnits: total,
                message: message
            )
        )
        try await client.emitEvent(envelope)
    }

    public func setWaiting(taskId: String, sessionId: String, reason: String, attention: Bool = true) async throws {
        let envelope = ATPEnvelope(
            eventType: .taskWaiting,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "cli"),
            sessionId: sessionId,
            taskId: taskId,
            payload: ATPPayload(reason: reason, attention: attention)
        )
        try await client.emitEvent(envelope)
    }

    public func setBlocked(taskId: String, sessionId: String, reason: String) async throws {
        let envelope = ATPEnvelope(
            eventType: .taskBlocked,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "cli"),
            sessionId: sessionId,
            taskId: taskId,
            payload: ATPPayload(reason: reason, attention: true)
        )
        try await client.emitEvent(envelope)
    }

    public func completeTask(taskId: String, sessionId: String, summary: String? = nil) async throws {
        let envelope = ATPEnvelope(
            eventType: .taskSucceeded,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "cli"),
            sessionId: sessionId,
            taskId: taskId,
            payload: ATPPayload(message: summary)
        )
        try await client.emitEvent(envelope)
    }

    public func failTask(taskId: String, sessionId: String, reason: String) async throws {
        let envelope = ATPEnvelope(
            eventType: .taskFailed,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "cli"),
            sessionId: sessionId,
            taskId: taskId,
            payload: ATPPayload(reason: reason)
        )
        try await client.emitEvent(envelope)
    }

    public func cancelTask(taskId: String, sessionId: String, reason: String) async throws {
        let envelope = ATPEnvelope(
            eventType: .taskCancelled,
            source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "cli"),
            sessionId: sessionId,
            taskId: taskId,
            payload: ATPPayload(reason: reason)
        )
        try await client.emitEvent(envelope)
    }
}
