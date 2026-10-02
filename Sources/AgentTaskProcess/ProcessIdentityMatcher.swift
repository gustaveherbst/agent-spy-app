import Foundation
import AgentTaskCore

public enum ProcessIdentityMatcher {
    /// Checks whether the process represented by `identity` is currently alive.
    /// If start time is recorded, also checks for PID recycling.
    public static func isProcessAlive(_ identity: ProcessIdentity) -> Bool {
        guard let current = ProcessInspector.inspect(pid: identity.pid) else {
            return false
        }

        // If we have an expected start time, verify it to guard against PID reuse
        if let recordedStart = identity.processStartedAt, let currentStart = current.processStartedAt {
            let diff = abs(currentStart.timeIntervalSince(recordedStart))
            // Start times within 1 second are considered the same process invocation
            if diff > 1.0 {
                return false // PID was recycled!
            }
        }

        return true
    }
}
