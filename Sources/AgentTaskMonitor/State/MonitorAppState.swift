import Foundation
import SwiftUI
import AppKit
import AgentTaskCore
import AgentTaskProtocol
import AgentTaskIPC
import AgentTaskAdapters

public typealias Task = AgentTaskCore.Task

@MainActor
public final class MonitorAppState: ObservableObject {
    @Published public var tasks: [Task] = []
    @Published public var sessions: [Session] = []
    @Published public var isConnected: Bool = false
    @Published public var preferences: AppPreferences = AppPreferences.load()
    @Published public var searchText: String = ""
    @Published public var expandedTaskIds: Set<String> = []
    @Published public var isHistoryPresented: Bool = false
    @Published public var isPreferencesPresented: Bool = false
    @Published public var currentDate: Date = Date()

    // MCP Server State
    @Published public var mcpServerRunning: Bool = false
    @Published public var mcpServerPort: Int = 8765
    @Published public var mcpLastError: String?

    private let client: IPCSocketClient
    private let mcpServer: MCPHTTPServer
    private var subscriptionTask: SwiftUI.Task<Void, Never>?
    private var durationTickTask: SwiftUI.Task<Void, Never>?

    public init(client: IPCSocketClient = IPCSocketClient()) {
        self.client = client
        self.mcpServer = MCPHTTPServer(client: client)
        self.mcpServerPort = preferences.mcpServerPort
        self.mcpServer.onStateChange = { [weak self] isRunning, error in
            SwiftUI.Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.mcpServerRunning = isRunning
                self.mcpLastError = error
            }
        }

        // 1. Immediately restore last-persisted cache from disk so tasks & history are instantly visible on relaunch
        if let cached = LocalTaskCache.load() {
            self.tasks = cached.tasks
            self.sessions = cached.sessions
            for t in cached.tasks where t.isRoot && !t.subtasks.isEmpty {
                self.expandedTaskIds.insert(t.id)
            }
        }

        startDurationTimer()
        startConnectionLoop()
        startMCPServerIfNeeded()
    }

    deinit {
        durationTickTask?.cancel()
        subscriptionTask?.cancel()
        mcpServer.stop()
    }

    public func startMCPServerIfNeeded() {
        if preferences.mcpServerEnabled {
            do {
                try mcpServer.start(port: preferences.mcpServerPort)
                self.mcpServerRunning = true
                self.mcpServerPort = preferences.mcpServerPort
                self.mcpLastError = nil
            } catch {
                self.mcpServerRunning = false
                self.mcpLastError = error.localizedDescription
            }
        } else {
            mcpServer.stop()
            self.mcpServerRunning = false
        }
    }

    public func setMCPServer(enabled: Bool, port: Int) {
        preferences.mcpServerEnabled = enabled
        preferences.mcpServerPort = port
        preferences.save()

        if enabled {
            do {
                try mcpServer.start(port: port)
                self.mcpServerRunning = true
                self.mcpServerPort = port
                self.mcpLastError = nil
            } catch {
                self.mcpServerRunning = false
                self.mcpLastError = error.localizedDescription
            }
        } else {
            mcpServer.stop()
            self.mcpServerRunning = false
            self.mcpLastError = nil
        }
    }

    public var mcpEndpointURLString: String {
        return "http://127.0.0.1:\(preferences.mcpServerPort)/sse"
    }

    public func copyClaudeConfig() {
        let json = """
        {
          "mcpServers": {
            "agentspy": {
              "url": "\(mcpEndpointURLString)"
            }
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    private func startDurationTimer() {
        durationTickTask?.cancel()
        durationTickTask = SwiftUI.Task { [weak self] in
            while !SwiftUI.Task.isCancelled {
                try? await SwiftUI.Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.currentDate = Date()
                }
            }
        }
    }

    public func startConnectionLoop() {
        subscriptionTask?.cancel()
        subscriptionTask = SwiftUI.Task { [weak self] in
            while !SwiftUI.Task.isCancelled {
                guard let self = self else { break }

                DaemonProcessManager.shared.ensureDaemonRunning()

                do {
                    try self.client.connect()
                    await MainActor.run {
                        self.isConnected = true
                    }

                    // Explicitly query latest SQLite snapshot on connect
                    if let snap = try? await self.client.getSnapshot() {
                        await MainActor.run {
                            self.applySnapshot(snap)
                        }
                    }

                    let stream = self.client.subscribe()
                    for await message in stream {
                        await MainActor.run {
                            self.handleServerMessage(message)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.isConnected = false
                    }
                }

                await MainActor.run {
                    self.isConnected = false
                }
                try? await SwiftUI.Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func applySnapshot(_ snap: TaskSnapshot) {
        self.tasks = snap.tasks
        self.sessions = snap.sessions
        for t in snap.tasks where t.isRoot && !t.subtasks.isEmpty {
            expandedTaskIds.insert(t.id)
        }
        LocalTaskCache.save(tasks: self.tasks, sessions: self.sessions)
    }

    private func handleServerMessage(_ message: IPCServerMessage) {
        switch message.type {
        case "snapshot":
            if let snap = message.snapshot {
                applySnapshot(snap)
            }

        case "task_update":
            if let updated = message.task {
                applyTaskUpdate(updated)
                LocalTaskCache.save(tasks: self.tasks, sessions: self.sessions)
            }

        default:
            break
        }
    }

    private func applyTaskUpdate(_ updated: Task) {
        if let idx = tasks.firstIndex(where: { $0.id == updated.id }) {
            let previous = tasks[idx]
            tasks[idx] = updated

            // Check notifications
            if preferences.notifyOnAttention && !previous.state.requiresAttention && updated.state.requiresAttention {
                NotificationManager.shared.notifyAttention(for: updated)
            } else if preferences.notifyOnFailure && !previous.state.isTerminal && updated.state == .failed {
                NotificationManager.shared.notifyFailure(for: updated)
            } else if preferences.notifyOnCompletion && !previous.state.isTerminal && updated.state == .succeeded && updated.isRoot {
                NotificationManager.shared.notifyCompletion(for: updated)
            }
        } else {
            tasks.insert(updated, at: 0)
            if updated.state.requiresAttention && preferences.notifyOnAttention {
                NotificationManager.shared.notifyAttention(for: updated)
            }
        }

        if !updated.subtasks.isEmpty {
            expandedTaskIds.insert(updated.id)
        }
    }

    // MARK: - Computed Properties

    public var activeTasks: [Task] {
        return tasks.filter { $0.state.isActive }
    }

    public var attentionTasks: [Task] {
        return tasks.filter { $0.attention || $0.state.requiresAttention }
    }

    public var completedTasks: [Task] {
        return tasks.filter { $0.state.isTerminal && $0.isRoot }
            .sorted { ($0.endedAt ?? $0.updatedAt) > ($1.endedAt ?? $1.updatedAt) }
    }

    public var activeRootTasks: [Task] {
        return tasks.filter { $0.isRoot && $0.state.isActive }
    }

    public var filteredTasks: [Task] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return tasks
        }
        let q = searchText.lowercased()
        return tasks.filter {
            $0.title.lowercased().contains(q) ||
            ($0.projectName?.lowercased().contains(q) ?? false) ||
            ($0.detail?.lowercased().contains(q) ?? false) ||
            $0.state.displayName.lowercased().contains(q)
        }
    }

    public var tasksGroupedByAgent: [(agent: String, tasks: [Task])] {
        let roots = activeRootTasks
        let sessionMap = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var groups: [String: [Task]] = [:]

        for t in roots {
            let agentName = sessionMap[t.sessionId]?.agent.uppercased() ?? "AGENT"
            groups[agentName, default: []].append(t)
        }

        return groups.map { (agent: $0.key, tasks: $0.value) }
            .sorted { $0.agent < $1.agent }
    }

    public var tasksGroupedByProject: [(project: String, tasks: [Task])] {
        let roots = activeRootTasks
        var groups: [String: [Task]] = [:]

        for t in roots {
            let pName = t.projectName ?? "General"
            groups[pName, default: []].append(t)
        }

        return groups.map { (project: $0.key, tasks: $0.value) }
            .sorted { $0.project < $1.project }
    }

    // MARK: - Actions

    public func toggleExpand(taskId: String) {
        if expandedTaskIds.contains(taskId) {
            expandedTaskIds.remove(taskId)
        } else {
            expandedTaskIds.insert(taskId)
        }
    }

    public func revealInFinder(task: Task) {
        guard let path = task.projectPath, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    public func openInTerminal(task: Task) {
        guard let path = task.projectPath, !path.isEmpty else { return }
        let script = "tell application \"Terminal\" to do script \"cd '\(path)'\""
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    public func copyTaskDetails(task: Task) {
        let text = """
        Task: \(task.title)
        State: \(task.state.displayName)
        Duration: \(task.formattedDuration(at: currentDate))
        Project: \(task.projectName ?? "-") (\(task.projectPath ?? "-"))
        ID: \(task.id)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func copyTaskId(task: Task) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.id, forType: .string)
    }

    public func cancelTask(task: Task) {
        SwiftUI.Task {
            let req = IPCClientRequest(type: "execute_action", taskId: task.id, actionId: "cancel")
            _ = try? await client.send(request: req)
        }
    }

    public func clearHistory() {
        tasks.removeAll(where: { $0.state.isTerminal })
        LocalTaskCache.save(tasks: self.tasks, sessions: self.sessions)
    }
}
