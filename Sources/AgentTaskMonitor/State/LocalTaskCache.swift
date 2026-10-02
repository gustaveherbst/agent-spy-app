import Foundation
import AgentTaskCore

public struct LocalTaskCache: Codable, Sendable {
    public var tasks: [AgentTaskCore.Task]
    public var sessions: [Session]
    public var savedAt: Date

    private static var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AgentTask", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tasks_cache.json")
    }

    public static func load() -> LocalTaskCache? {
        guard let data = try? Data(contentsOf: cacheFileURL) else { return nil }
        return try? JSONDecoder().decode(LocalTaskCache.self, from: data)
    }

    public static func save(tasks: [AgentTaskCore.Task], sessions: [Session]) {
        let cache = LocalTaskCache(tasks: tasks, sessions: sessions, savedAt: Date())
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }
}
