import Foundation

/// An agent session / invocation.
public struct Session: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var agent: String // "claude", "antigravity", "codex", "auggie", "opencode", "levax", "custom"
    public var adapter: String // "claude-code", "mcp", "cli", etc.
    public var title: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var metadata: [String: String]?

    public init(
        id: String,
        agent: String,
        adapter: String,
        title: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.agent = agent
        self.adapter = adapter
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.metadata = metadata
    }

    /// Whether session has completed.
    public var isEnded: Bool {
        return endedAt != nil
    }

    /// Agent name capitalized for display.
    public var agentDisplayName: String {
        return agent.uppercased()
    }
}
