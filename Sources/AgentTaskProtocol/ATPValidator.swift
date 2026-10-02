import Foundation
import AgentTaskCore

public enum ATPValidationError: Error, CustomStringConvertible, Sendable {
    case unsupportedProtocol(String)
    case missingEventId
    case missingSessionId
    case missingTaskId(ATPEventType)
    case invalidProgressFraction(Double)
    case invalidProgressUnits(completed: Double, total: Double)
    case stringTooLong(field: String, maxLength: Int)
    case invalidCharacters(field: String)
    case malformedJSON
    case serializationFailed

    public var description: String {
        switch self {
        case .unsupportedProtocol(let p):
            return "Unsupported ATP protocol version: '\(p)', expected 'atp/1'"
        case .missingEventId:
            return "Event ID is required and cannot be empty"
        case .missingSessionId:
            return "Session ID is required and cannot be empty"
        case .missingTaskId(let type):
            return "Task ID is required for event type '\(type.rawValue)'"
        case .invalidProgressFraction(let f):
            return "Progress fraction must be between 0.0 and 1.0, got \(f)"
        case .invalidProgressUnits(let c, let t):
            return "Invalid progress units: completed (\(c)) must be non-negative and total (\(t)) must be positive"
        case .stringTooLong(let field, let maxLen):
            return "Field '\(field)' exceeds maximum length of \(maxLen)"
        case .invalidCharacters(let field):
            return "Field '\(field)' contains invalid characters (e.g. null bytes)"
        case .malformedJSON:
            return "Malformed JSON input"
        case .serializationFailed:
            return "Failed to serialize event to JSON"
        }
    }
}

public struct ATPValidator: Sendable {
    public static let maxTitleLength = 512
    public static let maxDetailLength = 8192
    public static let maxMessageLength = 2048
    public static let maxReasonLength = 2048
    public static let maxIdLength = 128

    public init() {}

    /// Validates an incoming ATPEnvelope for protocol conformance and safety limits.
    public static func validate(_ envelope: ATPEnvelope) throws {
        // 1. Protocol version
        guard envelope.protocol.hasPrefix("atp/1") else {
            throw ATPValidationError.unsupportedProtocol(envelope.protocol)
        }

        // 2. IDs
        guard !envelope.eventId.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ATPValidationError.missingEventId
        }
        if envelope.eventId.count > maxIdLength {
            throw ATPValidationError.stringTooLong(field: "event_id", maxLength: maxIdLength)
        }

        guard !envelope.sessionId.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ATPValidationError.missingSessionId
        }
        if envelope.sessionId.count > maxIdLength {
            throw ATPValidationError.stringTooLong(field: "session_id", maxLength: maxIdLength)
        }

        // 3. Task ID required for task events and process.bound
        if envelope.eventType != .sessionRegistered && envelope.eventType != .sessionEnded {
            guard let tid = envelope.taskId, !tid.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ATPValidationError.missingTaskId(envelope.eventType)
            }
            if tid.count > maxIdLength {
                throw ATPValidationError.stringTooLong(field: "task_id", maxLength: maxIdLength)
            }
        }

        // 4. Validate payload strings
        if let title = envelope.payload.title {
            if title.contains("\0") {
                throw ATPValidationError.invalidCharacters(field: "title")
            }
            if title.count > maxTitleLength {
                throw ATPValidationError.stringTooLong(field: "title", maxLength: maxTitleLength)
            }
        }

        if let detail = envelope.payload.detail {
            if detail.contains("\0") {
                throw ATPValidationError.invalidCharacters(field: "detail")
            }
            if detail.count > maxDetailLength {
                throw ATPValidationError.stringTooLong(field: "detail", maxLength: maxDetailLength)
            }
        }

        if let reason = envelope.payload.reason {
            if reason.contains("\0") {
                throw ATPValidationError.invalidCharacters(field: "reason")
            }
            if reason.count > maxReasonLength {
                throw ATPValidationError.stringTooLong(field: "reason", maxLength: maxReasonLength)
            }
        }

        if let msg = envelope.payload.message {
            if msg.contains("\0") {
                throw ATPValidationError.invalidCharacters(field: "message")
            }
            if msg.count > maxMessageLength {
                throw ATPValidationError.stringTooLong(field: "message", maxLength: maxMessageLength)
            }
        }

        // 5. Validate progress
        if let fraction = envelope.payload.fraction {
            if fraction < 0.0 || fraction > 1.0 {
                throw ATPValidationError.invalidProgressFraction(fraction)
            }
        }

        if let completed = envelope.payload.completedUnits, let total = envelope.payload.totalUnits {
            if completed < 0 || total <= 0 {
                throw ATPValidationError.invalidProgressUnits(completed: completed, total: total)
            }
        }
    }
}
