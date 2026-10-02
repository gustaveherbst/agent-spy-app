import Foundation

/// Primary task abstraction representing meaningful work performed by an agent.
public struct Task: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var sessionId: String
    public var parentTaskId: String?
    public var title: String
    public var detail: String?
    public var state: TaskState
    public var projectName: String?
    public var projectPath: String?
    public var progress: TaskProgress?
    public var attention: Bool
    public var startedAt: Date?
    public var updatedAt: Date
    public var endedAt: Date?
    public var terminalReason: String?
    public var metadata: [String: String]?
    public var process: ProcessIdentity?
    public var actions: [TaskAction]
    public var subtasks: [Task]

    public init(
        id: String,
        sessionId: String,
        parentTaskId: String? = nil,
        title: String,
        detail: String? = nil,
        state: TaskState = .registered,
        projectName: String? = nil,
        projectPath: String? = nil,
        progress: TaskProgress? = nil,
        attention: Bool = false,
        startedAt: Date? = nil,
        updatedAt: Date = Date(),
        endedAt: Date? = nil,
        terminalReason: String? = nil,
        metadata: [String: String]? = nil,
        process: ProcessIdentity? = nil,
        actions: [TaskAction] = [],
        subtasks: [Task] = []
    ) {
        self.id = id
        self.sessionId = sessionId
        self.parentTaskId = parentTaskId
        self.title = title
        self.detail = detail
        self.state = state
        self.projectName = projectName
        self.projectPath = projectPath
        self.progress = progress
        self.attention = attention
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.endedAt = endedAt
        self.terminalReason = terminalReason
        self.metadata = metadata
        self.process = process
        self.actions = actions
        self.subtasks = subtasks
    }

    /// Whether this task is a top-level root task.
    public var isRoot: Bool {
        return parentTaskId == nil || parentTaskId?.isEmpty == true
    }

    /// Returns ProjectInfo convenience struct.
    public var project: ProjectInfo {
        return ProjectInfo(name: projectName, path: projectPath)
    }

    /// Calculates elapsed duration.
    public func elapsedDuration(at referenceDate: Date = Date()) -> TimeInterval {
        guard let start = startedAt else { return 0 }
        let end = endedAt ?? referenceDate
        return max(0, end.timeIntervalSince(start))
    }

    /// Returns human formatted duration string (e.g. "18m 43s", "4m", "32s", "1h 12m").
    public func formattedDuration(at referenceDate: Date = Date()) -> String {
        let seconds = Int(elapsedDuration(at: referenceDate))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remSeconds = seconds % 60
        if minutes < 60 {
            if remSeconds == 0 {
                return "\(minutes)m"
            }
            return "\(minutes)m \(remSeconds)s"
        }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        return "\(hours)h \(remMinutes)m"
    }
}
