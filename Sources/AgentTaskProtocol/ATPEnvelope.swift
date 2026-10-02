import Foundation
import AgentTaskCore

/// Source metadata describing the adapter and agent producing the event.
public struct ATPSource: Codable, Sendable, Equatable {
    public var adapter: String
    public var adapterVersion: String?
    public var agent: String

    public init(adapter: String, adapterVersion: String? = nil, agent: String) {
        self.adapter = adapter
        self.adapterVersion = adapterVersion
        self.agent = agent
    }

    enum CodingKeys: String, CodingKey {
        case adapter
        case adapterVersion = "adapter_version"
        case agent
    }
}

/// Generic payload for ATP events.
public struct ATPPayload: Codable, Sendable, Equatable {
    public var title: String?
    public var detail: String?
    public var project: ProjectInfo?
    public var process: ProcessIdentity?
    public var progress: TaskProgress?
    public var fraction: Double?
    public var completedUnits: Double?
    public var totalUnits: Double?
    public var message: String?
    public var reason: String?
    public var attention: Bool?
    public var actions: [TaskAction]?
    public var metadata: [String: String]?

    public init(
        title: String? = nil,
        detail: String? = nil,
        project: ProjectInfo? = nil,
        process: ProcessIdentity? = nil,
        progress: TaskProgress? = nil,
        fraction: Double? = nil,
        completedUnits: Double? = nil,
        totalUnits: Double? = nil,
        message: String? = nil,
        reason: String? = nil,
        attention: Bool? = nil,
        actions: [TaskAction]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.title = title
        self.detail = detail
        self.project = project
        self.process = process
        self.progress = progress
        self.fraction = fraction
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.message = message
        self.reason = reason
        self.attention = attention
        self.actions = actions
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case title
        case detail
        case project
        case process
        case progress
        case fraction
        case completedUnits = "completed_units"
        case totalUnits = "total_units"
        case message
        case reason
        case attention
        case actions
        case metadata
    }

    /// Resolves progress either from explicit TaskProgress struct or individual fields.
    public var resolvedProgress: TaskProgress? {
        if let p = progress { return p }
        if fraction != nil || completedUnits != nil || totalUnits != nil || message != nil {
            return TaskProgress(
                fraction: fraction,
                completedUnits: completedUnits,
                totalUnits: totalUnits,
                message: message
            )
        }
        return nil
    }
}

/// Canonical ATP v1 event envelope.
public struct ATPEnvelope: Codable, Sendable, Equatable {
    public var `protocol`: String
    public var eventId: String
    public var eventType: ATPEventType
    public var timestamp: Date
    public var source: ATPSource
    public var sessionId: String
    public var taskId: String?
    public var parentTaskId: String?
    public var payload: ATPPayload

    public init(
        protocol: String = "atp/1",
        eventId: String = ATPIdentifiers.newEventId(),
        eventType: ATPEventType,
        timestamp: Date = Date(),
        source: ATPSource,
        sessionId: String,
        taskId: String? = nil,
        parentTaskId: String? = nil,
        payload: ATPPayload = ATPPayload()
    ) {
        self.protocol = `protocol`
        self.eventId = eventId
        self.eventType = eventType
        self.timestamp = timestamp
        self.source = source
        self.sessionId = sessionId
        self.taskId = taskId
        self.parentTaskId = parentTaskId
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case `protocol`
        case eventId = "event_id"
        case eventType = "event_type"
        case timestamp
        case source
        case sessionId = "session_id"
        case taskId = "task_id"
        case parentTaskId = "parent_task_id"
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocol = try container.decode(String.self, forKey: .protocol)
        self.eventId = try container.decode(String.self, forKey: .eventId)
        self.eventType = try container.decode(ATPEventType.self, forKey: .eventType)

        let dateString = try container.decode(String.self, forKey: .timestamp)
        guard let date = ATPIdentifiers.parseDate(dateString) else {
            throw DecodingError.dataCorruptedError(forKey: .timestamp, in: container, debugDescription: "Invalid ISO8601 date: \(dateString)")
        }
        self.timestamp = date

        self.source = try container.decode(ATPSource.self, forKey: .source)
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        self.taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        self.parentTaskId = try container.decodeIfPresent(String.self, forKey: .parentTaskId)
        self.payload = try container.decodeIfPresent(ATPPayload.self, forKey: .payload) ?? ATPPayload()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.protocol, forKey: .protocol)
        try container.encode(self.eventId, forKey: .eventId)
        try container.encode(self.eventType, forKey: .eventType)
        try container.encode(ATPIdentifiers.formatDate(self.timestamp), forKey: .timestamp)
        try container.encode(self.source, forKey: .source)
        try container.encode(self.sessionId, forKey: .sessionId)
        try container.encodeIfPresent(self.taskId, forKey: .taskId)
        try container.encodeIfPresent(self.parentTaskId, forKey: .parentTaskId)
        try container.encode(self.payload, forKey: .payload)
    }

    /// Helper to convert to JSON string.
    public func toJSONString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ATPValidationError.serializationFailed
        }
        return string
    }

    /// Helper to decode from JSON string.
    public static func fromJSONString(_ json: String) throws -> ATPEnvelope {
        guard let data = json.data(using: .utf8) else {
            throw ATPValidationError.malformedJSON
        }
        let decoder = JSONDecoder()
        return try decoder.decode(ATPEnvelope.self, from: data)
    }
}
