import Foundation
import Network
import AgentTaskCore
import AgentTaskProtocol
import AgentTaskIPC

public final class MCPHTTPServer: @unchecked Sendable {
    public let client: IPCSocketClient
    private var listener: NWListener?
    private let lock = NSLock()
    private var activeSessions: [String: NWConnection] = [:]
    private var defaultSessionId: String = ""

    public private(set) var isRunning: Bool = false
    public private(set) var port: Int = 8765
    public private(set) var lastError: String?
    public var onStateChange: (@Sendable (Bool, String?) -> Void)?

    public init(client: IPCSocketClient = IPCSocketClient()) {
        self.client = client
    }

    deinit {
        stop()
    }

    public var sseEndpointURL: URL? {
        guard isRunning else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/sse")
    }

    public var httpEndpointURL: URL? {
        guard isRunning else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/mcp")
    }

    public func start(port: Int = 8765) throws {
        lock.lock()
        defer { lock.unlock() }

        if isRunning {
            if self.port == port { return }
            stopUnlocked()
        }

        self.port = port
        self.lastError = nil

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NSError(domain: "MCPHTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port: \(port)"])
        }

        let newListener = try NWListener(using: parameters, on: nwPort)
        newListener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.lock.lock()
                self.isRunning = true
                self.lastError = nil
                let cb = self.onStateChange
                self.lock.unlock()
                cb?(true, nil)
            case .failed(let error):
                self.lock.lock()
                self.isRunning = false
                self.lastError = error.localizedDescription
                let cb = self.onStateChange
                self.lock.unlock()
                cb?(false, error.localizedDescription)
            case .cancelled:
                self.lock.lock()
                self.isRunning = false
                let cb = self.onStateChange
                self.lock.unlock()
                cb?(false, nil)
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        newListener.start(queue: DispatchQueue(label: "com.agentspy.mcp.http", attributes: .concurrent))
        self.listener = newListener
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopUnlocked()
    }

    private func stopUnlocked() {
        listener?.cancel()
        listener = nil
        for (_, conn) in activeSessions {
            conn.cancel()
        }
        activeSessions.removeAll()
        isRunning = false
        let cb = self.onStateChange
        cb?(false, nil)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "com.agentspy.mcp.client", qos: .userInitiated))
        readHTTPRequest(connection: connection, accumulated: Data())
    }

    private func readHTTPRequest(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if error != nil {
                connection.cancel()
                return
            }

            var currentData = accumulated
            if let data = data {
                currentData.append(data)
            }

            // Check if HTTP header is complete (\r\n\r\n)
            if let headerEnd = currentData.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = currentData.subdata(in: 0..<headerEnd.lowerBound)
                let bodyData = currentData.subdata(in: headerEnd.upperBound..<currentData.count)
                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    connection.cancel()
                    return
                }

                // Check Content-Length for POST requests
                var contentLength = 0
                for line in headerString.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let parts = line.components(separatedBy: ":")
                        if parts.count >= 2, let len = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                            contentLength = len
                        }
                    }
                }

                if bodyData.count < contentLength {
                    // Need more body data
                    self.readHTTPRequest(connection: connection, accumulated: currentData)
                    return
                }

                self.dispatchHTTPRequest(headerString: headerString, bodyData: bodyData, connection: connection)
            } else if !isComplete {
                self.readHTTPRequest(connection: connection, accumulated: currentData)
            } else {
                connection.cancel()
            }
        }
    }

    private func dispatchHTTPRequest(headerString: String, bodyData: Data, connection: NWConnection) {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            connection.cancel()
            return
        }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }

        let method = parts[0].uppercased()
        let fullPath = parts[1]
        let path = fullPath.components(separatedBy: "?").first ?? fullPath

        // CORS Preflight
        if method == "OPTIONS" {
            let response = "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\nContent-Length: 0\r\n\r\n"
            sendRaw(response, to: connection) { connection.cancel() }
            return
        }

        // Status / Info
        if (method == "GET" && (path == "/" || path == "/status" || path == "/health")) {
            let statusJSON: [String: Any] = [
                "name": "AgentSpy MCP Server",
                "version": "1.0.0",
                "status": "ready",
                "transport": ["sse", "http_jsonrpc"],
                "endpoints": [
                    "sse": "http://127.0.0.1:\(port)/sse",
                    "http": "http://127.0.0.1:\(port)/mcp"
                ]
            ]
            sendJSONResponse(statusJSON, to: connection)
            return
        }

        // Server-Sent Events (SSE) Registration
        if method == "GET" && path == "/sse" {
            let sessionId = "mcp_sess_" + UUID().uuidString.lowercased().prefix(8)
            lock.lock()
            activeSessions[sessionId] = connection
            lock.unlock()

            let sseHeaders = """
            HTTP/1.1 200 OK\r
            Content-Type: text/event-stream\r
            Cache-Control: no-cache\r
            Connection: keep-alive\r
            Access-Control-Allow-Origin: *\r
            \r\n
            """
            sendRaw(sseHeaders, to: connection)

            let endpointEvent = "event: endpoint\ndata: /messages?sessionId=\(sessionId)\n\n"
            sendRaw(endpointEvent, to: connection)
            return
        }

        // Handle JSON-RPC POST (either /messages, /mcp, or /)
        if method == "POST" && (path == "/messages" || path == "/mcp" || path == "/") {
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
                sendHTTPError(code: 400, message: "Invalid JSON", to: connection)
                return
            }

            // Extract sessionId query param if present
            var sessionId: String?
            if let query = fullPath.components(separatedBy: "?").dropFirst().first {
                for item in query.components(separatedBy: "&") {
                    let pair = item.components(separatedBy: "=")
                    if pair.count == 2 && pair[0] == "sessionId" {
                        sessionId = pair[1]
                    }
                }
            }

            _Concurrency.Task {
                let responseDict = await self.processJSONRPC(json: json)
                if let respData = try? JSONSerialization.data(withJSONObject: responseDict),
                   let respStr = String(data: respData, encoding: .utf8) {

                    // If an active SSE session exists for this sessionId, also broadcast over SSE
                    if let sId = sessionId, let sseConn = self.sessionConnection(for: sId) {
                        let sseMsg = "event: message\ndata: \(respStr)\n\n"
                        self.sendRaw(sseMsg, to: sseConn)
                    }

                    // And return direct HTTP 200 response
                    self.sendJSONResponse(responseDict, to: connection)
                } else {
                    self.sendHTTPError(code: 500, message: "Internal server error", to: connection)
                }
            }
            return
        }

        // Not Found
        sendHTTPError(code: 404, message: "Not Found", to: connection)
    }

    private func processJSONRPC(json: [String: Any]) async -> [String: Any] {
        guard let method = json["method"] as? String else {
            return ["jsonrpc": "2.0", "id": json["id"] ?? NSNull(), "error": ["code": -32600, "message": "Invalid Request"]]
        }
        let id = json["id"]

        switch method {
        case "initialize":
            return [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "result": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [
                        "tools": ["listChanged": false]
                    ],
                    "serverInfo": [
                        "name": "agentspy-mcp",
                        "version": "1.0.0"
                    ]
                ]
            ]

        case "notifications/initialized":
            return ["jsonrpc": "2.0", "result": [:]]

        case "ping":
            return ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": [:]]

        case "tools/list":
            return [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "result": [
                    "tools": getToolDefinitions()
                ]
            ]

        case "tools/call":
            guard let params = json["params"] as? [String: Any],
                  let toolName = params["name"] as? String else {
                return ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": -32602, "message": "Invalid params"]]
            }
            let args = (params["arguments"] as? [String: Any]) ?? [:]
            do {
                let text = try await executeTool(name: toolName, arguments: args)
                return [
                    "jsonrpc": "2.0",
                    "id": id ?? NSNull(),
                    "result": [
                        "content": [
                            ["type": "text", "text": text]
                        ]
                    ]
                ]
            } catch {
                return [
                    "jsonrpc": "2.0",
                    "id": id ?? NSNull(),
                    "error": [
                        "code": -32000,
                        "message": error.localizedDescription
                    ]
                ]
            }

        default:
            return ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": -32601, "message": "Method not found: \(method)"]]
        }
    }

    private func executeTool(name: String, arguments: [String: Any]) async throws -> String {
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
                source: ATPSource(adapter: "mcp-http", adapterVersion: "1.0.0", agent: agent),
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

            let envelope = ATPEnvelope(
                eventType: .taskStarted,
                source: ATPSource(adapter: "mcp-http", adapterVersion: "1.0.0", agent: "mcp"),
                sessionId: sessionId.isEmpty ? "session_default" : sessionId,
                taskId: taskId,
                parentTaskId: parentTaskId,
                payload: ATPPayload(title: title, detail: detail, project: ProjectInfo(name: projectName, path: project))
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
                source: ATPSource(adapter: "mcp-http", adapterVersion: "1.0.0", agent: "mcp"),
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
                source: ATPSource(adapter: "mcp-http", adapterVersion: "1.0.0", agent: "mcp"),
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
                source: ATPSource(adapter: "mcp-http", adapterVersion: "1.0.0", agent: "mcp"),
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
                source: ATPSource(adapter: "mcp-http", adapterVersion: "1.0.0", agent: "mcp"),
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
                source: ATPSource(adapter: "mcp-http", adapterVersion: "1.0.0", agent: "mcp"),
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
                source: ATPSource(adapter: "mcp-http", adapterVersion: "1.0.0", agent: "mcp"),
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
                "description": "Registers an agent session with AgentSpy.",
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

    private func sessionConnection(for sessionId: String) -> NWConnection? {
        lock.lock()
        defer { lock.unlock() }
        return activeSessions[sessionId]
    }

    private func sendRaw(_ string: String, to connection: NWConnection, completion: (@Sendable () -> Void)? = nil) {
        guard let data = string.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in
            completion?()
        })
    }

    private func sendJSONResponse(_ dict: [String: Any], to connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            sendHTTPError(code: 500, message: "Internal Serialization Error", to: connection)
            return
        }
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r\n
        """
        var responseData = headers.data(using: .utf8)!
        responseData.append(data)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendHTTPError(code: Int, message: String, to connection: NWConnection) {
        let body = "{\"error\": \"\(message)\"}"
        let headers = """
        HTTP/1.1 \(code) \(message)\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r\n
        """
        sendRaw(headers + body, to: connection) {
            connection.cancel()
        }
    }
}
