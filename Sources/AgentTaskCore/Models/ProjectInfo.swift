import Foundation

/// Project metadata associated with an agent or task.
public struct ProjectInfo: Codable, Sendable, Equatable {
    public var name: String?
    public var path: String?
    public var repository: String?

    public init(name: String? = nil, path: String? = nil, repository: String? = nil) {
        self.name = name
        self.path = path
        self.repository = repository
    }

    /// Display label: either project name or last component of path or "Unknown".
    public var displayName: String {
        if let name = name, !name.isEmpty { return name }
        if let path = path, !path.isEmpty { return (path as NSString).lastPathComponent }
        return "Unknown Project"
    }

    /// Abbreviated path (e.g. ~/dev/project).
    public var abbreviatedPath: String {
        guard let path = path, !path.isEmpty else { return "" }
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
