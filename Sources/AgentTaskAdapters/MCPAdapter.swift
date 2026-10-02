import Foundation
import AgentTaskCore
import AgentTaskProtocol
import AgentTaskIPC
import AgentTaskProcess

public final class MCPAdapter: AgentAdapter, @unchecked Sendable {
    public let adapterId = "mcp"
    public let capabilities = AdapterCapabilities(
        canDiscoverSession: true,
        canReportTaskLifecycle: true,
        canReportProgress: true,
        canReportSubtasks: true,
        canReportAttention: true,
        canDeepLink: false,
        canCancel: true
    )

    public let client: IPCSocketClient
    private var defaultSessionId: String = ""

    public init(client: IPCSocketClient = IPCSocketClient()) {
        self.client = client
    }

    /// Runs the stdio MCP server loop.
    public func runStdio() async {
        let inputHandle = FileHandle.standardInput
        var buffer = Data()

        while true {
            let chunk = inputHandle.availableData
            if chunk.isEmpty {
                break // EOF
            }
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.subdata(in: 0..<newlineIndex)
                buffer.removeSubrange(0...newlineIndex)

                if let line = String(data: lineData, encoding: .utf8), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    await handleJSONRPCMessage(line)
                }
            }
        }
    }

    private func handleJSONRPCMessage(_ line: String) async {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else {
            return
        }

        let id = json["id"]

        switch method {
        case "initialize":
            let result: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": ["listChanged": false]
                ],
                "serverInfo": [
                    "name": "agenttask-mcp",
                    "version": "1.0.0"
                ]
            ]
            sendResponse(id: id, result: result)

        case "notifications/initialized":
            // No response required for notification
            break

        case "ping":
            sendResponse(id: id, result: [:])

        case "tools/list":
            let tools = getToolDefinitions()
            sendResponse(id: id, result: ["tools": tools])

        case "tools/call":
            guard let params = json["params"] as? [String: Any],
                  let toolName = params["name"] as? String else {
                sendError(id: id, code: -32602, message: "Invalid params")
                return
            }
            let arguments = (params["arguments"] as? [String: Any]) ?? [:]
            do {
                let resultText = try await handleToolCall(name: toolName, arguments: arguments)
                let result: [String: Any] = [
                    "content": [
                        ["type": "text", "text": resultText]
                    ]
                ]
                sendResponse(id: id, result: result)
            } catch {
                sendError(id: id, code: -32000, message: "Tool execution failed: \(error.localizedDescription)")
            }

        default:
            sendError(id: id, code: -32601, message: "Method '\(method)' not found")
        }
    }

    private func handleToolCall(name: String, arguments: [String: Any]) async throws -> String {
        switch name {
        case "agent_task_session_register":
            let agent = (arguments["agent"] as? String) ?? "mcp-agent"
            let title = arguments["title"] as? String
            let project = arguments["project"] as? String
            let sessionId = ATPIdentifiers.newSessionId()
            self.defaultSessionId = sessionId

            let projectName = project != nil ? (project! as NSString).lastPathComponent : nil
            let envelope = ATPEnvelope(
                eventType: .sessionRegistered,
                source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: agent),
                sessionId: sessionId,
                payload: ATPPayload(title: title ?? "MCP Session", project: ProjectInfo(name: projectName, path: project))
            )
            try await client.emitEvent(envelope)
            return "Session registered with id: \(sessionId)"

        case "agent_task_start":
            let title = (arguments["title"] as? String) ?? "Untitled Task"
            let detail = arguments["detail"] as? String
            let parentTaskId = arguments["parent_task_id"] as? String
            let project = arguments["project"] as? String
            let sessionId = (arguments["session_id"] as? String) ?? defaultSessionId
            let taskId = ATPIdentifiers.newTaskId()

            let projectName = project != nil ? (project! as NSString).lastPathComponent : nil
            let proc = ProcessInspector.currentProcess()

            let envelope = ATPEnvelope(
                eventType: .taskStarted,
                source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "mcp"),
                sessionId: sessionId.isEmpty ? "session_default" : sessionId,
                taskId: taskId,
                parentTaskId: parentTaskId,
                payload: ATPPayload(title: title, detail: detail, project: ProjectInfo(name: projectName, path: project), process: proc)
            )
            try await client.emitEvent(envelope)
            return "Task started with id: \(taskId)"

        case "agent_task_progress":
            guard let taskId = arguments["task_id"] as? String else {
                throw ATPValidationError.missingTaskId(.taskProgress)
            }
            let fraction = arguments["fraction"] as? Double
            let completed = (arguments["completed"] as? NSNumber)?.doubleValue
            let total = (arguments["total"] as? NSNumber)?.doubleValue
            let message = arguments["message"] as? String

            let envelope = ATPEnvelope(
                eventType: .taskProgress,
                source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "mcp"),
                sessionId: defaultSessionId.isEmpty ? "session_default" : defaultSessionId,
                taskId: taskId,
                payload: ATPPayload(fraction: fraction, completedUnits: completed, totalUnits: total, message: message)
            )
            try await client.emitEvent(envelope)
            return "Progress recorded for task: \(taskId)"

        case "agent_task_waiting":
            guard let taskId = arguments["task_id"] as? String else {
                throw ATPValidationError.missingTaskId(.taskWaiting)
            }
            let reason = (arguments["reason"] as? String) ?? "Waiting for input"
            let attention = (arguments["attention"] as? Bool) ?? true

            let envelope = ATPEnvelope(
                eventType: .taskWaiting,
                source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "mcp"),
                sessionId: defaultSessionId.isEmpty ? "session_default" : defaultSessionId,
                taskId: taskId,
                payload: ATPPayload(reason: reason, attention: attention)
            )
            try await client.emitEvent(envelope)
            return "Task set to waiting: \(taskId)"

        case "agent_task_blocked":
            guard let taskId = arguments["task_id"] as? String else {
                throw ATPValidationError.missingTaskId(.taskBlocked)
            }
            let reason = (arguments["reason"] as? String) ?? "Task blocked"

            let envelope = ATPEnvelope(
                eventType: .taskBlocked,
                source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "mcp"),
                sessionId: defaultSessionId.isEmpty ? "session_default" : defaultSessionId,
                taskId: taskId,
                payload: ATPPayload(reason: reason, attention: true)
            )
            try await client.emitEvent(envelope)
            return "Task blocked: \(taskId)"

        case "agent_task_complete":
            guard let taskId = arguments["task_id"] as? String else {
                throw ATPValidationError.missingTaskId(.taskSucceeded)
            }
            let summary = arguments["summary"] as? String

            let envelope = ATPEnvelope(
                eventType: .taskSucceeded,
                source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "mcp"),
                sessionId: defaultSessionId.isEmpty ? "session_default" : defaultSessionId,
                taskId: taskId,
                payload: ATPPayload(message: summary)
            )
            try await client.emitEvent(envelope)
            return "Task completed: \(taskId)"

        case "agent_task_fail":
            guard let taskId = arguments["task_id"] as? String else {
                throw ATPValidationError.missingTaskId(.taskFailed)
            }
            let reason = (arguments["reason"] as? String) ?? "Task failed"

            let envelope = ATPEnvelope(
                eventType: .taskFailed,
                source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "mcp"),
                sessionId: defaultSessionId.isEmpty ? "session_default" : defaultSessionId,
                taskId: taskId,
                payload: ATPPayload(reason: reason)
            )
            try await client.emitEvent(envelope)
            return "Task marked failed: \(taskId)"

        case "agent_task_cancelled":
            guard let taskId = arguments["task_id"] as? String else {
                throw ATPValidationError.missingTaskId(.taskCancelled)
            }
            let reason = (arguments["reason"] as? String) ?? "Cancelled"

            let envelope = ATPEnvelope(
                eventType: .taskCancelled,
                source: ATPSource(adapter: adapterId, adapterVersion: "1.0.0", agent: "mcp"),
                sessionId: defaultSessionId.isEmpty ? "session_default" : defaultSessionId,
                taskId: taskId,
                payload: ATPPayload(reason: reason)
            )
            try await client.emitEvent(envelope)
            return "Task cancelled: \(taskId)"

        default:
            throw ATPValidationError.missingTaskId(.taskStarted)
        }
    }

    private func getToolDefinitions() -> [[String: Any]] {
        return [
            [
                "name": "agent_task_session_register",
                "description": "Registers an agent session with AgentTaskMonitor.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "agent": ["type": "string", "description": "Agent name (e.g. claude, antigravity, custom)"],
                        "title": ["type": "string", "description": "Session goal or description"],
                        "project": ["type": "string", "description": "Project directory path"]
                    ],
                    "required": ["agent"]
                ]
            ],
            [
                "name": "agent_task_start",
                "description": "Starts and registers a new root task or subtask.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Short, human-meaningful task title"],
                        "detail": ["type": "string", "description": "Optional extended description"],
                        "session_id": ["type": "string", "description": "Optional session identifier"],
                        "parent_task_id": ["type": "string", "description": "Parent task ID if this is a subtask"],
                        "project": ["type": "string", "description": "Project path"]
                    ],
                    "required": ["title"]
                ]
            ],
            [
                "name": "agent_task_progress",
                "description": "Reports measurable progress on an active task. Never report invented percentages.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string", "description": "Task identifier"],
                        "fraction": ["type": "number", "description": "Fraction between 0.0 and 1.0 (if measurable)"],
                        "completed": ["type": "number", "description": "Completed work units"],
                        "total": ["type": "number", "description": "Total work units"],
                        "message": ["type": "string", "description": "Progress message (e.g. Step 504/800)"]
                    ],
                    "required": ["task_id"]
                ]
            ],
            [
                "name": "agent_task_waiting",
                "description": "Marks a task as waiting for developer input or confirmation.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string", "description": "Task identifier"],
                        "reason": ["type": "string", "description": "Explanation of what input or action is needed"],
                        "attention": ["type": "boolean", "description": "Whether to highlight with attention badge"]
                    ],
                    "required": ["task_id", "reason"]
                ]
            ],
            [
                "name": "agent_task_blocked",
                "description": "Marks a task as blocked by an external dependency or error.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string", "description": "Task identifier"],
                        "reason": ["type": "string", "description": "Reason task is blocked"]
                    ],
                    "required": ["task_id", "reason"]
                ]
            ],
            [
                "name": "agent_task_complete",
                "description": "Marks a task as successfully completed.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string", "description": "Task identifier"],
                        "summary": ["type": "string", "description": "Optional summary of outcome"]
                    ],
                    "required": ["task_id"]
                ]
            ],
            [
                "name": "agent_task_fail",
                "description": "Marks a task as failed.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string", "description": "Task identifier"],
                        "reason": ["type": "string", "description": "Failure reason or error message"]
                    ],
                    "required": ["task_id", "reason"]
                ]
            ],
            [
                "name": "agent_task_cancelled",
                "description": "Marks a task as cancelled.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string", "description": "Task identifier"],
                        "reason": ["type": "string", "description": "Cancellation reason"]
                    ],
                    "required": ["task_id"]
                ]
            ]
        ]
    }

    private func sendResponse(id: Any?, result: [String: Any]) {
        guard let id = id else { return }
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
        sendJSON(response)
    }

    private func sendError(id: Any?, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ]
        sendJSON(response)
    }

    private func sendJSON(_ dict: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           var str = String(data: data, encoding: .utf8) {
            str.append("\n")
            if let outData = str.data(using: .utf8) {
                FileHandle.standardOutput.write(outData)
            }
        }
    }
}
