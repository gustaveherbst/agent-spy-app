import Foundation

/// Progress information for a task.
public struct TaskProgress: Codable, Sendable, Equatable {
    /// Progress fraction between 0.0 and 1.0 (if measurable). Never invent fake percentages.
    public var fraction: Double?
    /// Completed units (e.g. 504 steps)
    public var completedUnits: Double?
    /// Total units (e.g. 800 steps)
    public var totalUnits: Double?
    /// Progress status message (e.g. "Training step 504/800")
    public var message: String?

    public init(
        fraction: Double? = nil,
        completedUnits: Double? = nil,
        totalUnits: Double? = nil,
        message: String? = nil
    ) {
        if let f = fraction {
            self.fraction = max(0.0, min(1.0, f))
        } else if let c = completedUnits, let t = totalUnits, t > 0 {
            self.fraction = max(0.0, min(1.0, c / t))
        } else {
            self.fraction = nil
        }
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.message = message
    }

    /// Formatted percentage string (e.g. "63%") or nil if unmeasurable.
    public var percentageText: String? {
        guard let fraction = fraction else { return nil }
        return "\(Int(round(fraction * 100)))%"
    }

    /// Short human summary of progress.
    public var summaryText: String {
        if let c = completedUnits, let t = totalUnits {
            let cStr = c.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(c)) : String(format: "%.1f", c)
            let tStr = t.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(t)) : String(format: "%.1f", t)
            if let p = percentageText {
                return "\(cStr)/\(tStr) (\(p))"
            }
            return "\(cStr)/\(tStr)"
        }
        if let p = percentageText {
            return p
        }
        return message ?? ""
    }
}
