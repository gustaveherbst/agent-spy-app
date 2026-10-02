import Foundation
import AgentTaskCore
import AgentTaskProtocol

/// Incoming request message from an IPC client to the daemon.
public struct IPCClientRequest: Codable, Sendable {
    public var id: String
    public var type: String // "emit_event", "subscribe", "get_snapshot", "get_task", "ping", "execute_action"
    public var event: ATPEnvelope?
    public var taskId: String?
    public var actionId: String?

    public init(id: String = UUID().uuidString, type: String, event: ATPEnvelope? = nil, taskId: String? = nil, actionId: String? = nil) {
        self.id = id
        self.type = type
        self.event = event
        self.taskId = taskId
        self.actionId = actionId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case event
        case taskId = "task_id"
        case actionId = "action_id"
    }
}

/// Outgoing response/stream message from the daemon to an IPC client.
public struct IPCServerMessage: Codable, Sendable {
    public var type: String // "response", "snapshot", "task_update", "event_broadcast", "pong"
    public var replyTo: String?
    public var status: String? // "ok", "error"
    public var error: String?
    public var snapshot: TaskSnapshot?
    public var task: Task?
    public var event: ATPEnvelope?

    public init(
        type: String,
        replyTo: String? = nil,
        status: String? = nil,
        error: String? = nil,
        snapshot: TaskSnapshot? = nil,
        task: Task? = nil,
        event: ATPEnvelope? = nil
    ) {
        self.type = type
        self.replyTo = replyTo
        self.status = status
        self.error = error
        self.snapshot = snapshot
        self.task = task
        self.event = event
    }

    enum CodingKeys: String, CodingKey {
        case type
        case replyTo = "reply_to"
        case status
        case error
        case snapshot
        case task
        case event
    }

    public static func ok(replyTo: String) -> IPCServerMessage {
        return IPCServerMessage(type: "response", replyTo: replyTo, status: "ok")
    }

    public static func failure(replyTo: String, error: String) -> IPCServerMessage {
        return IPCServerMessage(type: "response", replyTo: replyTo, status: "error", error: error)
    }

    public static func snapshotMessage(_ snapshot: TaskSnapshot, replyTo: String? = nil) -> IPCServerMessage {
        return IPCServerMessage(type: "snapshot", replyTo: replyTo, status: "ok", snapshot: snapshot)
    }

    public static func taskUpdate(_ task: Task) -> IPCServerMessage {
        return IPCServerMessage(type: "task_update", task: task)
    }

    public static func eventBroadcast(_ event: ATPEnvelope) -> IPCServerMessage {
        return IPCServerMessage(type: "event_broadcast", event: event)
    }
}
