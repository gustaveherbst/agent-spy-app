import Foundation

/// Event types defined in Agent Task Protocol (ATP) v1.
public enum ATPEventType: String, Codable, Sendable, CaseIterable {
    // Session events
    case sessionRegistered = "session.registered"
    case sessionEnded = "session.ended"

    // Task lifecycle events
    case taskRegistered = "task.registered"
    case taskStarted = "task.started"
    case taskProgress = "task.progress"
    case taskUpdated = "task.updated"
    case taskWaiting = "task.waiting"
    case taskBlocked = "task.blocked"
    case taskSucceeded = "task.succeeded"
    case taskFailed = "task.failed"
    case taskCancelled = "task.cancelled"
    case taskHeartbeat = "task.heartbeat"

    // Process binding
    case processBound = "process.bound"

    /// Whether this event implies a task state transition.
    public var targetTaskState: String? {
        switch self {
        case .taskRegistered:
            return "registered"
        case .taskStarted:
            return "running"
        case .taskWaiting:
            return "waiting"
        case .taskBlocked:
            return "blocked"
        case .taskSucceeded:
            return "succeeded"
        case .taskFailed:
            return "failed"
        case .taskCancelled:
            return "cancelled"
        default:
            return nil
        }
    }
}
