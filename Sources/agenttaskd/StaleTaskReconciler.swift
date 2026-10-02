import Foundation
import AgentTaskCore
import AgentTaskStore
import AgentTaskProcess

public final class StaleTaskReconciler: @unchecked Sendable {
    public let store: TaskStore
    public let livenessMonitor: ProcessLivenessMonitor

    public init(store: TaskStore, livenessMonitor: ProcessLivenessMonitor) {
        self.store = store
        self.livenessMonitor = livenessMonitor
    }

    /// Reconciles task states on daemon startup.
    public func reconcileStartup() throws -> [Task] {
        let activeTasks = try store.fetchActiveTasks()
        var reconciled: [Task] = []

        for var task in activeTasks {
            if let proc = task.process {
                let isAlive = ProcessIdentityMatcher.isProcessAlive(proc)
                if isAlive {
                    // Valid live process: continue monitoring
                    livenessMonitor.track(taskId: task.id, process: proc)
                    reconciled.append(task)
                } else {
                    // Process is dead: reconcile to aborted
                    task.state = .aborted
                    task.terminalReason = "process_lost"
                    task.endedAt = Date()
                    task.updatedAt = Date()
                    task.attention = false
                    try store.upsertTask(task)
                    reconciled.append(task)
                }
            } else {
                // Heartbeat-based or non-process task: keep active
                reconciled.append(task)
            }
        }

        return reconciled
    }

    /// Reconciles a task when its bound process is permanently lost after grace period.
    public func reconcileLostProcess(taskId: String, process: ProcessIdentity) throws -> Task? {
        guard var task = try store.fetchTask(id: taskId) else { return nil }
        guard !task.state.isTerminal else { return nil }

        task.state = .aborted
        task.terminalReason = "process_lost"
        task.endedAt = Date()
        task.updatedAt = Date()
        task.attention = false

        try store.upsertTask(task)
        return task
    }
}
