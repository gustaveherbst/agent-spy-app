import Foundation

/// Normalized states for a task according to the Agent Task Protocol (ATP).
public enum TaskState: String, Codable, Sendable, CaseIterable {
    case registered
    case queued
    case running
    case waiting
    case blocked
    case succeeded
    case failed
    case cancelled
    case aborted
    case unknown

    /// Whether this state is terminal (no further transitions allowed).
    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .aborted:
            return true
        case .registered, .queued, .running, .waiting, .blocked, .unknown:
            return false
        }
    }

    /// Whether this task is considered active in the menu bar.
    public var isActive: Bool {
        switch self {
        case .running, .queued, .waiting, .blocked:
            return true
        case .registered, .succeeded, .failed, .cancelled, .aborted, .unknown:
            return false
        }
    }

    /// Whether this task requires developer attention.
    public var requiresAttention: Bool {
        switch self {
        case .waiting, .blocked:
            return true
        default:
            return false
        }
    }

    /// SF Symbol name representing this state.
    public var symbolName: String {
        switch self {
        case .registered:
            return "doc.badge.plus"
        case .queued:
            return "clock"
        case .running:
            return "circle.inset.filled"
        case .waiting:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "nosign"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .cancelled:
            return "slash.circle"
        case .aborted:
            return "bolt.horizontal.circle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    /// Human readable label.
    public var displayName: String {
        switch self {
        case .registered:
            return "Registered"
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .waiting:
            return "Waiting for Input"
        case .blocked:
            return "Blocked"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .aborted:
            return "Aborted"
        case .unknown:
            return "Unknown"
        }
    }

    /// Checks if a transition from `self` to `target` is valid.
    public func canTransition(to target: TaskState) -> Bool {
        if self == target { return true }
        if self.isTerminal { return false } // Terminal states cannot transition back

        switch self {
        case .registered:
            return target == .queued || target == .running || target == .cancelled || target == .aborted
        case .queued:
            return target == .running || target == .cancelled || target == .aborted
        case .running:
            return true // can transition to waiting, blocked, or any terminal state
        case .waiting, .blocked:
            return target == .running || target.isTerminal
        case .unknown:
            return true
        case .succeeded, .failed, .cancelled, .aborted:
            return false
        }
    }
}
