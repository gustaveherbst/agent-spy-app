import Foundation

/// Snapshot of the complete state of the task monitor system.
public struct TaskSnapshot: Codable, Sendable {
    public var tasks: [Task]
    public var sessions: [Session]
    public var timestamp: Date

    public init(tasks: [Task] = [], sessions: [Session] = [], timestamp: Date = Date()) {
        self.tasks = tasks
        self.sessions = sessions
        self.timestamp = timestamp
    }

    /// Tasks that are currently active (running, queued, waiting, blocked).
    public var activeTasks: [Task] {
        return tasks.filter { $0.state.isActive }
    }

    /// Tasks that currently require attention.
    public var attentionTasks: [Task] {
        return tasks.filter { $0.attention || $0.state.requiresAttention }
    }

    /// Active root tasks.
    public var activeRootTasks: [Task] {
        return tasks.filter { $0.isRoot && $0.state.isActive }
    }

    /// Recently completed tasks (succeeded, failed, cancelled, aborted).
    public var completedTasks: [Task] {
        return tasks.filter { $0.state.isTerminal }
            .sorted { ($0.endedAt ?? $0.updatedAt) > ($1.endedAt ?? $1.updatedAt) }
    }
}
