import Foundation
import AgentTaskCore
import AgentTaskProtocol
import AgentTaskIPC
import AgentTaskProcess
import AgentTaskAdapters

@main
struct AgentTaskCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else {
            printHelp()
            exit(0)
        }

        let command = args[0]
        let subArgs = Array(args.dropFirst())

        do {
            let client = IPCSocketClient()
            let adapter = CLIAdapter(client: client)

            switch command {
            case "session":
                try await handleSession(subArgs: subArgs, adapter: adapter, client: client)

            case "start":
                try await handleStart(subArgs: subArgs, adapter: adapter, client: client)

            case "progress":
                try await handleProgress(subArgs: subArgs, adapter: adapter, client: client)

            case "waiting":
                try await handleWaiting(subArgs: subArgs, adapter: adapter, client: client)

            case "blocked":
                try await handleBlocked(subArgs: subArgs, adapter: adapter, client: client)

            case "done", "complete", "succeed":
                try await handleDone(subArgs: subArgs, adapter: adapter, client: client)

            case "fail":
                try await handleFail(subArgs: subArgs, adapter: adapter, client: client)

            case "cancel":
                try await handleCancel(subArgs: subArgs, adapter: adapter, client: client)

            case "list":
                try await handleList(subArgs: subArgs, client: client)

            case "status":
                try await handleStatus(subArgs: subArgs, client: client)

            case "run":
                try await handleRun(subArgs: subArgs, adapter: adapter, client: client)

            case "mcp":
                let mcpAdapter = MCPAdapter(client: client)
                await mcpAdapter.runStdio()

            case "mcp-server":
                var port = 8765
                if let pIdx = subArgs.firstIndex(of: "--port"), pIdx + 1 < subArgs.count, let p = Int(subArgs[pIdx + 1]) {
                    port = p
                }
                let server = MCPHTTPServer(client: client)
                try server.start(port: port)
                print("AgentSpy MCP HTTP/SSE Server running on http://127.0.0.1:\(port)")
                print("  SSE Endpoint:  http://127.0.0.1:\(port)/sse")
                print("  HTTP Endpoint: http://127.0.0.1:\(port)/mcp")
                dispatchMain()

            case "--help", "-h", "help":
                printHelp()

            default:
                fputs("Unknown command: \(command)\n", stderr)
                printHelp()
                exit(1)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    // MARK: - Handlers

    static func handleSession(subArgs: [String], adapter: CLIAdapter, client: IPCSocketClient) async throws {
        guard !subArgs.isEmpty else {
            fputs("Usage: agenttask session [start|end] [options]\n", stderr)
            exit(1)
        }
        let action = subArgs[0]
        let rest = Array(subArgs.dropFirst())

        switch action {
        case "start":
            var agent = "custom"
            var project: String? = FileManager.default.currentDirectoryPath
            var title: String?
            var jsonOutput = false

            var i = 0
            while i < rest.count {
                switch rest[i] {
                case "--agent":
                    if i + 1 < rest.count { agent = rest[i + 1]; i += 1 }
                case "--project":
                    if i + 1 < rest.count { project = rest[i + 1]; i += 1 }
                case "--title":
                    if i + 1 < rest.count { title = rest[i + 1]; i += 1 }
                case "--json":
                    jsonOutput = true
                default: break
                }
                i += 1
            }

            let sessionId = try await adapter.startSession(agent: agent, project: project, title: title)
            if jsonOutput {
                print("{\"session_id\":\"\(sessionId)\"}")
            } else {
                print("Started session: \(sessionId)")
            }

        case "end":
            guard !rest.isEmpty else {
                fputs("Usage: agenttask session end <session-id>\n", stderr)
                exit(1)
            }
            let sessionId = rest[0]
            try await adapter.endSession(sessionId: sessionId)
            print("Ended session: \(sessionId)")

        default:
            fputs("Unknown session action: \(action)\n", stderr)
            exit(1)
        }
    }

    static func handleStart(subArgs: [String], adapter: CLIAdapter, client: IPCSocketClient) async throws {
        var title: String = "Untitled Task"
        var parentId: String?
        var project: String? = FileManager.default.currentDirectoryPath
        var detail: String?
        var sessionId: String?
        var pid: Int32?
        var jsonOutput = false

        var i = 0
        while i < subArgs.count {
            switch subArgs[i] {
            case "--title":
                if i + 1 < subArgs.count { title = subArgs[i + 1]; i += 1 }
            case "--parent":
                if i + 1 < subArgs.count { parentId = subArgs[i + 1]; i += 1 }
            case "--project":
                if i + 1 < subArgs.count { project = subArgs[i + 1]; i += 1 }
            case "--detail":
                if i + 1 < subArgs.count { detail = subArgs[i + 1]; i += 1 }
            case "--session":
                if i + 1 < subArgs.count { sessionId = subArgs[i + 1]; i += 1 }
            case "--pid":
                if i + 1 < subArgs.count, let p = Int32(subArgs[i + 1]) { pid = p; i += 1 }
            case "--json":
                jsonOutput = true
            default: break
            }
            i += 1
        }

        // If no session provided, find active session or create default
        let actualSessionId: String
        if let s = sessionId {
            actualSessionId = s
        } else {
            let snap = try? await client.getSnapshot()
            if let activeSession = snap?.sessions.first(where: { !$0.isEnded }) {
                actualSessionId = activeSession.id
            } else {
                actualSessionId = try await adapter.startSession(agent: "cli", project: project, title: "CLI Session")
            }
        }

        let taskId = try await adapter.startTask(
            title: title,
            sessionId: actualSessionId,
            parentTaskId: parentId,
            detail: detail,
            project: project,
            pid: pid
        )

        if jsonOutput {
            print("{\"task_id\":\"\(taskId)\",\"session_id\":\"\(actualSessionId)\"}")
        } else {
            print("Started task: \(taskId)")
        }
    }

    static func handleProgress(subArgs: [String], adapter: CLIAdapter, client: IPCSocketClient) async throws {
        guard !subArgs.isEmpty else {
            fputs("Usage: agenttask progress <task-id> [options]\n", stderr)
            exit(1)
        }
        let taskId = subArgs[0]
        var fraction: Double?
        var completed: Double?
        var total: Double?
        var message: String?
        var sessionId = "session_default"

        var i = 1
        while i < subArgs.count {
            switch subArgs[i] {
            case "--fraction":
                if i + 1 < subArgs.count, let f = Double(subArgs[i + 1]) { fraction = f; i += 1 }
            case "--completed":
                if i + 1 < subArgs.count, let c = Double(subArgs[i + 1]) { completed = c; i += 1 }
            case "--total":
                if i + 1 < subArgs.count, let t = Double(subArgs[i + 1]) { total = t; i += 1 }
            case "--message":
                if i + 1 < subArgs.count { message = subArgs[i + 1]; i += 1 }
            case "--session":
                if i + 1 < subArgs.count { sessionId = subArgs[i + 1]; i += 1 }
            default: break
            }
            i += 1
        }

        try await adapter.reportProgress(
            taskId: taskId,
            sessionId: sessionId,
            fraction: fraction,
            completed: completed,
            total: total,
            message: message
        )
        print("Progress updated for task \(taskId)")
    }

    static func handleWaiting(subArgs: [String], adapter: CLIAdapter, client: IPCSocketClient) async throws {
        guard !subArgs.isEmpty else {
            fputs("Usage: agenttask waiting <task-id> --reason <reason>\n", stderr)
            exit(1)
        }
        let taskId = subArgs[0]
        var reason = "Waiting for input"
        var attention = true
        var sessionId = "session_default"

        var i = 1
        while i < subArgs.count {
            switch subArgs[i] {
            case "--reason":
                if i + 1 < subArgs.count { reason = subArgs[i + 1]; i += 1 }
            case "--attention":
                attention = true
            case "--session":
                if i + 1 < subArgs.count { sessionId = subArgs[i + 1]; i += 1 }
            default: break
            }
            i += 1
        }

        try await adapter.setWaiting(taskId: taskId, sessionId: sessionId, reason: reason, attention: attention)
        print("Task \(taskId) set to waiting: \(reason)")
    }

    static func handleBlocked(subArgs: [String], adapter: CLIAdapter, client: IPCSocketClient) async throws {
        guard !subArgs.isEmpty else {
            fputs("Usage: agenttask blocked <task-id> --reason <reason>\n", stderr)
            exit(1)
        }
        let taskId = subArgs[0]
        var reason = "Task blocked"
        var sessionId = "session_default"

        var i = 1
        while i < subArgs.count {
            switch subArgs[i] {
            case "--reason":
                if i + 1 < subArgs.count { reason = subArgs[i + 1]; i += 1 }
            case "--session":
                if i + 1 < subArgs.count { sessionId = subArgs[i + 1]; i += 1 }
            default: break
            }
            i += 1
        }

        try await adapter.setBlocked(taskId: taskId, sessionId: sessionId, reason: reason)
        print("Task \(taskId) marked blocked: \(reason)")
    }

    static func handleDone(subArgs: [String], adapter: CLIAdapter, client: IPCSocketClient) async throws {
        guard !subArgs.isEmpty else {
            fputs("Usage: agenttask done <task-id> [--summary <summary>]\n", stderr)
            exit(1)
        }
        let taskId = subArgs[0]
        var summary: String?
        var sessionId = "session_default"

        var i = 1
        while i < subArgs.count {
            switch subArgs[i] {
            case "--summary":
                if i + 1 < subArgs.count { summary = subArgs[i + 1]; i += 1 }
            case "--session":
                if i + 1 < subArgs.count { sessionId = subArgs[i + 1]; i += 1 }
            default: break
            }
            i += 1
        }

        try await adapter.completeTask(taskId: taskId, sessionId: sessionId, summary: summary)
        print("Task \(taskId) marked complete")
    }

    static func handleFail(subArgs: [String], adapter: CLIAdapter, client: IPCSocketClient) async throws {
        guard !subArgs.isEmpty else {
            fputs("Usage: agenttask fail <task-id> --reason <reason>\n", stderr)
            exit(1)
        }
        let taskId = subArgs[0]
        var reason = "Task failed"
        var sessionId = "session_default"

        var i = 1
        while i < subArgs.count {
            switch subArgs[i] {
            case "--reason":
                if i + 1 < subArgs.count { reason = subArgs[i + 1]; i += 1 }
            case "--session":
                if i + 1 < subArgs.count { sessionId = subArgs[i + 1]; i += 1 }
            default: break
            }
            i += 1
        }

        try await adapter.failTask(taskId: taskId, sessionId: sessionId, reason: reason)
        print("Task \(taskId) marked failed: \(reason)")
    }

    static func handleCancel(subArgs: [String], adapter: CLIAdapter, client: IPCSocketClient) async throws {
        guard !subArgs.isEmpty else {
            fputs("Usage: agenttask cancel <task-id> --reason <reason>\n", stderr)
            exit(1)
        }
        let taskId = subArgs[0]
        var reason = "Cancelled by user"
        var sessionId = "session_default"

        var i = 1
        while i < subArgs.count {
            switch subArgs[i] {
            case "--reason":
                if i + 1 < subArgs.count { reason = subArgs[i + 1]; i += 1 }
            case "--session":
                if i + 1 < subArgs.count { sessionId = subArgs[i + 1]; i += 1 }
            default: break
            }
            i += 1
        }

        try await adapter.cancelTask(taskId: taskId, sessionId: sessionId, reason: reason)
        print("Task \(taskId) cancelled: \(reason)")
    }

    static func handleList(subArgs: [String], client: IPCSocketClient) async throws {
        var activeOnly = false
        var jsonOutput = false

        for arg in subArgs {
            if arg == "--active" { activeOnly = true }
            if arg == "--json" { jsonOutput = true }
        }

        let snap = try await client.getSnapshot()
        let tasks = activeOnly ? snap.activeTasks : snap.tasks

        if jsonOutput {
            let data = try JSONEncoder().encode(tasks)
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            if tasks.isEmpty {
                print("No \(activeOnly ? "active " : "")tasks found.")
                return
            }
            let headerId = "ID".padding(toLength: 16, withPad: " ", startingAt: 0)
            let headerState = "STATE".padding(toLength: 12, withPad: " ", startingAt: 0)
            let headerTitle = "TITLE".padding(toLength: 25, withPad: " ", startingAt: 0)
            print("\(headerId) \(headerState) \(headerTitle) PROJECT")
            print(String(repeating: "─", count: 75))
            for t in tasks {
                let idPrefix = String(t.id.prefix(14)).padding(toLength: 16, withPad: " ", startingAt: 0)
                let stateStr = t.state.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
                let titlePrefix = String(t.title.prefix(24)).padding(toLength: 25, withPad: " ", startingAt: 0)
                let proj = t.projectName ?? "-"
                print("\(idPrefix) \(stateStr) \(titlePrefix) \(proj)")
            }
        }
    }

    static func handleStatus(subArgs: [String], client: IPCSocketClient) async throws {
        guard !subArgs.isEmpty else {
            fputs("Usage: agenttask status <task-id> [--json]\n", stderr)
            exit(1)
        }
        let taskId = subArgs[0]
        let jsonOutput = subArgs.contains("--json")

        let req = IPCClientRequest(type: "get_task", taskId: taskId)
        let resp = try await client.send(request: req)
        guard let task = resp.task else {
            fputs("Task not found: \(taskId)\n", stderr)
            exit(1)
        }

        if jsonOutput {
            let data = try JSONEncoder().encode(task)
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("Task: \(task.title) (\(task.id))")
            print("  State: \(task.state.displayName)")
            print("  Duration: \(task.formattedDuration())")
            if let prj = task.projectName { print("  Project: \(prj)") }
            if let prog = task.progress { print("  Progress: \(prog.summaryText)") }
            if let det = task.detail { print("  Detail: \(det)") }
            if !task.subtasks.isEmpty {
                print("  Subtasks (\(task.subtasks.count)):")
                for sub in task.subtasks {
                    print("    - [\(sub.state.displayName)] \(sub.title)")
                }
            }
        }
    }

    static func handleRun(subArgs: [String], adapter: CLIAdapter, client: IPCSocketClient) async throws {
        var title = "Command Run"
        var parentId: String?
        var project: String? = FileManager.default.currentDirectoryPath
        var commandParts: [String] = []

        var i = 0
        while i < subArgs.count {
            if subArgs[i] == "--" {
                commandParts = Array(subArgs.dropFirst(i + 1))
                break
            } else if subArgs[i] == "--title" && i + 1 < subArgs.count {
                title = subArgs[i + 1]
                i += 1
            } else if subArgs[i] == "--parent" && i + 1 < subArgs.count {
                parentId = subArgs[i + 1]
                i += 1
            } else if subArgs[i] == "--project" && i + 1 < subArgs.count {
                project = subArgs[i + 1]
                i += 1
            }
            i += 1
        }

        guard !commandParts.isEmpty else {
            fputs("Usage: agenttask run --title <title> [--parent <id>] -- <command...>\n", stderr)
            exit(1)
        }

        let snap = try? await client.getSnapshot()
        let sessionId: String
        if let existing = snap?.sessions.first(where: { !$0.isEnded })?.id {
            sessionId = existing
        } else {
            sessionId = try await adapter.startSession(agent: "cli", project: project, title: "Run Session")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = commandParts
        if let p = project {
            proc.currentDirectoryURL = URL(fileURLWithPath: p)
        }

        try proc.run()
        let pid = proc.processIdentifier

        let taskId = try await adapter.startTask(
            title: title,
            sessionId: sessionId,
            parentTaskId: parentId,
            detail: commandParts.joined(separator: " "),
            project: project,
            pid: pid
        )

        print("Spawned process (PID \(pid)), tracking under task \(taskId)...")
        proc.waitUntilExit()
        let exitCode = proc.terminationStatus

        if exitCode == 0 {
            try await adapter.completeTask(taskId: taskId, sessionId: sessionId, summary: "Exited with code 0")
            print("Task \(taskId) succeeded.")
        } else {
            try await adapter.failTask(taskId: taskId, sessionId: sessionId, reason: "Exited with code \(exitCode)")
            print("Task \(taskId) failed with code \(exitCode).")
            exit(exitCode)
        }
    }

    static func printHelp() {
        print("""
        agenttask — CLI for Agent Task Monitor

        Usage:
          agenttask session start --agent <name> [--project <path>] [--title <title>] [--json]
          agenttask session end <session-id>
          agenttask start --title <title> [--parent <id>] [--project <path>] [--detail <text>] [--pid <pid>] [--json]
          agenttask progress <task-id> [--fraction <0.0-1.0>] [--completed <N> --total <M>] [--message <msg>]
          agenttask waiting <task-id> --reason <reason> [--attention]
          agenttask blocked <task-id> --reason <reason>
          agenttask done <task-id> [--summary <summary>]
          agenttask fail <task-id> --reason <reason>
          agenttask cancel <task-id> --reason <reason>
          agenttask list [--active] [--json]
          agenttask status <task-id> [--json]
          agenttask run --title <title> [--parent <id>] [--project <path>] -- <command...>
          agenttask mcp
          agenttask mcp-server [--port <port>]
        """)
    }
}
