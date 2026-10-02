import Foundation

/// Action advertised by an adapter for a task (e.g. open URL, reveal in Finder, cancel).
public struct TaskAction: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var kind: String // "open_url", "focus_application", "reveal_path", "invoke_adapter_action", "cancel"
    public var payload: [String: String]?

    public init(id: String, label: String, kind: String, payload: [String: String]? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.payload = payload
    }
}
