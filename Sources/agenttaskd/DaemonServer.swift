import Foundation
import AgentTaskCore
import AgentTaskProtocol
import AgentTaskStore
import AgentTaskProcess
import AgentTaskIPC

public final class DaemonServer: @unchecked Sendable {
    public let store: TaskStore
    public let livenessMonitor: ProcessLivenessMonitor
    public let reducer: TaskReducer
    public let reconciler: StaleTaskReconciler
    public let socketServer: IPCSocketServer
    private let queue = DispatchQueue(label: "com.agenttask.daemon.server", qos: .userInitiated)

    public init(
        socketPath: String = IPCConstants.defaultSocketPath(),
        store: TaskStore? = nil,
        pollingInterval: TimeInterval = 2.0,
        gracePeriod: TimeInterval = 4.0
    ) throws {
        let actualStore = try (store ?? TaskStore.default())
        let monitor = ProcessLivenessMonitor(pollingInterval: pollingInterval, gracePeriod: gracePeriod)
        let red = TaskReducer(store: actualStore, livenessMonitor: monitor)
        let rec = StaleTaskReconciler(store: actualStore, livenessMonitor: monitor)
        let server = IPCSocketServer(socketPath: socketPath)

        self.store = actualStore
        self.livenessMonitor = monitor
        self.reducer = red
        self.reconciler = rec
        self.socketServer = server

        setupLivenessCallbacks()
        setupRequestHandler()
    }

    private func setupLivenessCallbacks() {
        livenessMonitor.onProcessLost = { [weak self] taskId, proc in
            guard let self = self else { return }
            self.queue.async {
                do {
                    if let abortedTask = try self.reconciler.reconcileLostProcess(taskId: taskId, process: proc) {
                        // Broadcast the updated task and snapshot to UI clients
                        self.socketServer.broadcast(IPCServerMessage.taskUpdate(abortedTask))
                        if let snap = try? self.buildSnapshot() {
                            self.socketServer.broadcast(IPCServerMessage.snapshotMessage(snap))
                        }
                    }
                } catch {
                    // Log error
                }
            }
        }
    }

    private func setupRequestHandler() {
        socketServer.onRequest = { [weak self] request, clientFd in
            guard let self = self else { return }
            self.queue.async {
                self.handleRequest(request, from: clientFd)
            }
        }
    }

    private func handleRequest(_ request: IPCClientRequest, from fd: Int32) {
        switch request.type {
        case "emit_event":
            guard let envelope = request.event else {
                socketServer.send(IPCServerMessage.failure(replyTo: request.id, error: "Missing event payload"), to: fd)
                return
            }
            do {
                let result = try reducer.reduce(envelope: envelope)
                socketServer.send(IPCServerMessage.ok(replyTo: request.id), to: fd)

                if let task = result.task {
                    socketServer.broadcast(IPCServerMessage.taskUpdate(task))
                }
                socketServer.broadcast(IPCServerMessage.eventBroadcast(envelope))
                if let snap = try? buildSnapshot() {
                    socketServer.broadcast(IPCServerMessage.snapshotMessage(snap))
                }
            } catch {
                socketServer.send(IPCServerMessage.failure(replyTo: request.id, error: error.localizedDescription), to: fd)
            }

        case "get_snapshot":
            do {
                let snap = try buildSnapshot()
                socketServer.send(IPCServerMessage.snapshotMessage(snap, replyTo: request.id), to: fd)
            } catch {
                socketServer.send(IPCServerMessage.failure(replyTo: request.id, error: error.localizedDescription), to: fd)
            }

        case "subscribe":
            do {
                let snap = try buildSnapshot()
                socketServer.send(IPCServerMessage.snapshotMessage(snap, replyTo: request.id), to: fd)
            } catch {
                socketServer.send(IPCServerMessage.failure(replyTo: request.id, error: error.localizedDescription), to: fd)
            }

        case "get_task":
            guard let tid = request.taskId else {
                socketServer.send(IPCServerMessage.failure(replyTo: request.id, error: "Missing task_id"), to: fd)
                return
            }
            do {
                let task = try store.fetchTask(id: tid)
                var msg = IPCServerMessage.ok(replyTo: request.id)
                msg.task = task
                socketServer.send(msg, to: fd)
            } catch {
                socketServer.send(IPCServerMessage.failure(replyTo: request.id, error: error.localizedDescription), to: fd)
            }

        case "ping":
            socketServer.send(IPCServerMessage.ok(replyTo: request.id), to: fd)

        case "execute_action":
            guard let tid = request.taskId, let aid = request.actionId else {
                socketServer.send(IPCServerMessage.failure(replyTo: request.id, error: "Missing task_id or action_id"), to: fd)
                return
            }
            do {
                if aid == "cancel" {
                    if var task = try store.fetchTask(id: tid) {
                        task.state = .cancelled
                        task.endedAt = Date()
                        task.terminalReason = "User cancelled"
                        try store.upsertTask(task)
                        socketServer.broadcast(IPCServerMessage.taskUpdate(task))
                    }
                }
                socketServer.send(IPCServerMessage.ok(replyTo: request.id), to: fd)
            } catch {
                socketServer.send(IPCServerMessage.failure(replyTo: request.id, error: error.localizedDescription), to: fd)
            }

        default:
            socketServer.send(IPCServerMessage.failure(replyTo: request.id, error: "Unknown request type: \(request.type)"), to: fd)
        }
    }

    public func buildSnapshot() throws -> TaskSnapshot {
        let tasks = try store.fetchAllTasks()
        let sessions = try store.fetchAllSessions()
        return TaskSnapshot(tasks: tasks, sessions: sessions, timestamp: Date())
    }

    public func start() throws {
        // 1. Startup reconciliation
        _ = try reconciler.reconcileStartup()

        // 2. Start socket server
        try socketServer.start()

        // 3. Start process monitoring
        livenessMonitor.start()
    }

    public func stop() {
        livenessMonitor.stop()
        socketServer.stop()
    }
}
