import Foundation
import AgentTaskCore
import AgentTaskProtocol
import AgentTaskStore
import AgentTaskProcess

public final class TaskReducer: @unchecked Sendable {
    public let store: TaskStore
    public let livenessMonitor: ProcessLivenessMonitor

    public init(store: TaskStore, livenessMonitor: ProcessLivenessMonitor) {
        self.store = store
        self.livenessMonitor = livenessMonitor
    }

    /// Reducer result containing the updated task or session, and whether it was newly created/updated.
    public struct ReduceResult: Sendable {
        public var task: Task?
        public var session: Session?
        public var wasDeduplicated: Bool
    }

    /// Ingests and applies an ATP envelope idempotently.
    public func reduce(envelope: ATPEnvelope) throws -> ReduceResult {
        // 1. Validate envelope
        try ATPValidator.validate(envelope)

        // 2. Check deduplication
        if try store.isEventProcessed(eventId: envelope.eventId) {
            if let tid = envelope.taskId, let existing = try store.fetchTask(id: tid) {
                return ReduceResult(task: existing, session: nil, wasDeduplicated: true)
            }
            if let s = try store.fetchSession(id: envelope.sessionId) {
                return ReduceResult(task: nil, session: s, wasDeduplicated: true)
            }
            return ReduceResult(task: nil, session: nil, wasDeduplicated: true)
        }

        // 3. Process according to event type
        var updatedTask: Task?
        var updatedSession: Session?

        if envelope.eventType != .sessionRegistered && envelope.eventType != .sessionEnded {
            try ensureSessionExists(envelope)
        }

        switch envelope.eventType {
        case .sessionRegistered:
            var session = (try store.fetchSession(id: envelope.sessionId)) ?? Session(
                id: envelope.sessionId,
                agent: envelope.source.agent,
                adapter: envelope.source.adapter,
                title: envelope.payload.title,
                startedAt: envelope.timestamp
            )
            session.title = envelope.payload.title ?? session.title
            session.metadata = envelope.payload.metadata ?? session.metadata
            try store.upsertSession(session)
            updatedSession = session

        case .sessionEnded:
            if var session = try store.fetchSession(id: envelope.sessionId) {
                session.endedAt = envelope.timestamp
                try store.upsertSession(session)
                updatedSession = session
            }

        case .taskRegistered:
            let taskId = envelope.taskId!
            var task = (try store.fetchTask(id: taskId)) ?? Task(
                id: taskId,
                sessionId: envelope.sessionId,
                parentTaskId: envelope.parentTaskId,
                title: envelope.payload.title ?? "Untitled Task",
                state: .registered,
                updatedAt: envelope.timestamp
            )
            applyPayload(envelope.payload, to: &task)
            task.state = .registered
            task.updatedAt = envelope.timestamp
            try store.upsertTask(task)
            updatedTask = task

        case .taskStarted:
            let taskId = envelope.taskId!
            var task = (try store.fetchTask(id: taskId)) ?? Task(
                id: taskId,
                sessionId: envelope.sessionId,
                parentTaskId: envelope.parentTaskId,
                title: envelope.payload.title ?? "Untitled Task",
                state: .running,
                updatedAt: envelope.timestamp
            )
            applyPayload(envelope.payload, to: &task)
            task.state = .running
            if task.startedAt == nil {
                task.startedAt = envelope.timestamp
            }
            task.updatedAt = envelope.timestamp
            try store.upsertTask(task)
            updatedTask = task

        case .taskProgress:
            let taskId = envelope.taskId!
            guard var task = try store.fetchTask(id: taskId) else { break }
            if let prog = envelope.payload.resolvedProgress {
                task.progress = prog
            }
            task.updatedAt = envelope.timestamp
            try store.upsertTask(task)
            updatedTask = task

        case .taskUpdated:
            let taskId = envelope.taskId!
            guard var task = try store.fetchTask(id: taskId) else { break }
            applyPayload(envelope.payload, to: &task)
            task.updatedAt = envelope.timestamp
            try store.upsertTask(task)
            updatedTask = task

        case .taskWaiting:
            let taskId = envelope.taskId!
            guard var task = try store.fetchTask(id: taskId) else { break }
            task.state = .waiting
            task.attention = envelope.payload.attention ?? true
            task.detail = envelope.payload.reason ?? task.detail
            task.terminalReason = envelope.payload.reason
            task.updatedAt = envelope.timestamp
            try store.upsertTask(task)
            updatedTask = task

        case .taskBlocked:
            let taskId = envelope.taskId!
            guard var task = try store.fetchTask(id: taskId) else { break }
            task.state = .blocked
            task.attention = true
            task.detail = envelope.payload.reason ?? task.detail
            task.terminalReason = envelope.payload.reason
            task.updatedAt = envelope.timestamp
            try store.upsertTask(task)
            updatedTask = task

        case .taskSucceeded:
            let taskId = envelope.taskId!
            guard var task = try store.fetchTask(id: taskId) else { break }
            task.state = .succeeded
            task.attention = false
            task.endedAt = envelope.timestamp
            task.updatedAt = envelope.timestamp
            if let msg = envelope.payload.message {
                task.detail = msg
            }
            try store.upsertTask(task)
            updatedTask = task

        case .taskFailed:
            let taskId = envelope.taskId!
            guard var task = try store.fetchTask(id: taskId) else { break }
            task.state = .failed
            task.attention = true
            task.endedAt = envelope.timestamp
            task.updatedAt = envelope.timestamp
            task.terminalReason = envelope.payload.reason ?? "Task execution failed"
            try store.upsertTask(task)
            updatedTask = task

        case .taskCancelled:
            let taskId = envelope.taskId!
            guard var task = try store.fetchTask(id: taskId) else { break }
            task.state = .cancelled
            task.attention = false
            task.endedAt = envelope.timestamp
            task.updatedAt = envelope.timestamp
            task.terminalReason = envelope.payload.reason ?? "Task cancelled"
            try store.upsertTask(task)
            updatedTask = task

        case .taskHeartbeat:
            let taskId = envelope.taskId!
            if var task = try store.fetchTask(id: taskId) {
                task.updatedAt = envelope.timestamp
                try store.upsertTask(task)
                updatedTask = task
            }

        case .processBound:
            let taskId = envelope.taskId!
            if var task = try store.fetchTask(id: taskId), let proc = envelope.payload.process {
                task.process = proc
                task.updatedAt = envelope.timestamp
                try store.upsertTask(task)
                updatedTask = task
            }
        }

        // 4. Update ProcessLivenessMonitor tracking
        if let task = updatedTask {
            if task.state.isActive, let proc = task.process {
                livenessMonitor.track(taskId: task.id, process: proc)
            } else if task.state.isTerminal {
                livenessMonitor.untrack(taskId: task.id)
            }
        }

        // 5. Record event in database for deduplication and audit trail
        let payloadJson = (try? envelope.payload.toJSONString()) ?? "{}"
        try store.recordEvent(
            eventId: envelope.eventId,
            taskId: envelope.taskId,
            sessionId: envelope.sessionId,
            eventType: envelope.eventType.rawValue,
            timestamp: envelope.timestamp,
            sourceAdapter: envelope.source.adapter,
            payloadJSON: payloadJson
        )

        return ReduceResult(task: updatedTask, session: updatedSession, wasDeduplicated: false)
    }

    private func applyPayload(_ payload: ATPPayload, to task: inout Task) {
        if let t = payload.title { task.title = t }
        if let d = payload.detail { task.detail = d }
        if let prj = payload.project {
            if let n = prj.name { task.projectName = n }
            if let p = prj.path { task.projectPath = p }
        }
        if let prog = payload.resolvedProgress { task.progress = prog }
        if let att = payload.attention { task.attention = att }
        if let proc = payload.process { task.process = proc }
        if let actions = payload.actions { task.actions = actions }
        if let meta = payload.metadata { task.metadata = meta }
    }

    private func ensureSessionExists(_ envelope: ATPEnvelope) throws {
        if try store.fetchSession(id: envelope.sessionId) == nil {
            let session = Session(
                id: envelope.sessionId,
                agent: envelope.source.agent,
                adapter: envelope.source.adapter,
                title: envelope.payload.title ?? "Session",
                startedAt: envelope.timestamp
            )
            try store.upsertSession(session)
        }
    }
}

private extension ATPPayload {
    func toJSONString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
