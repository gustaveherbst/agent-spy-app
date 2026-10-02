import Foundation

/// Grouping mode for tasks in the menu bar popup.
public enum TaskGroupingMode: String, Codable, Sendable, CaseIterable {
    case byAgent = "agent"
    case byProject = "project"
    case flat = "flat"

    public var displayName: String {
        switch self {
        case .byAgent: return "Group by Agent"
        case .byProject: return "Group by Project"
        case .flat: return "Flat List"
        }
    }
}

/// User preferences for the Agent Task Monitor app.
public struct AppPreferences: Codable, Sendable, Equatable {
    public var launchAtLogin: Bool
    public var showActiveCount: Bool
    public var completedTaskRetention: Int
    public var notifyOnAttention: Bool
    public var notifyOnFailure: Bool
    public var notifyOnCompletion: Bool
    public var staleTaskTimeoutSeconds: Double
    public var processPollingIntervalSeconds: Double
    public var groupingMode: TaskGroupingMode
    public var mcpServerEnabled: Bool
    public var mcpServerPort: Int

    public init(
        launchAtLogin: Bool = false,
        showActiveCount: Bool = true,
        completedTaskRetention: Int = 50,
        notifyOnAttention: Bool = true,
        notifyOnFailure: Bool = true,
        notifyOnCompletion: Bool = true,
        staleTaskTimeoutSeconds: Double = 30.0,
        processPollingIntervalSeconds: Double = 3.0,
        groupingMode: TaskGroupingMode = .byAgent,
        mcpServerEnabled: Bool = true,
        mcpServerPort: Int = 8765
    ) {
        self.launchAtLogin = launchAtLogin
        self.showActiveCount = showActiveCount
        self.completedTaskRetention = completedTaskRetention
        self.notifyOnAttention = notifyOnAttention
        self.notifyOnFailure = notifyOnFailure
        self.notifyOnCompletion = notifyOnCompletion
        self.staleTaskTimeoutSeconds = staleTaskTimeoutSeconds
        self.processPollingIntervalSeconds = processPollingIntervalSeconds
        self.groupingMode = groupingMode
        self.mcpServerEnabled = mcpServerEnabled
        self.mcpServerPort = mcpServerPort
    }

    public static let `default` = AppPreferences()

    private static let userDefaultsKey = "com.agentspy.preferences"

    public static func load() -> AppPreferences {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let prefs = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            return prefs
        }
        return .default
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
