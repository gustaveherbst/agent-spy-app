import Foundation

/// Utility for generating normalized IDs and timestamps.
public enum ATPIdentifiers: Sendable {
    /// Generates a unique event ID.
    public static func newEventId() -> String {
        return "evt_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// Generates a unique task ID.
    public static func newTaskId() -> String {
        return "task_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// Generates a unique session ID.
    public static func newSessionId() -> String {
        return "session_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    private static let lock = NSLock()

    nonisolated(unsafe) private static let _iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let _iso8601BasicFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses an ISO-8601 date string.
    public static func parseDate(_ string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        if let d = _iso8601Formatter.date(from: string) {
            return d
        }
        return _iso8601BasicFormatter.date(from: string)
    }

    /// Formats a Date to ISO-8601 string.
    public static func formatDate(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return _iso8601Formatter.string(from: date)
    }
}
