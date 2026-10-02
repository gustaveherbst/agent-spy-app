import Foundation
import AgentTaskCore

public final class ProcessLivenessMonitor: @unchecked Sendable {
    private struct TrackedBinding {
        var taskId: String
        var process: ProcessIdentity
        var firstMissingAt: Date?
    }

    private var tracked: [String: TrackedBinding] = [:]
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.agenttask.liveness", qos: .utility)

    public var pollingInterval: TimeInterval = 2.0
    public var gracePeriod: TimeInterval = 4.0

    public var onProcessLost: (@Sendable (String, ProcessIdentity) -> Void)?
    public var onProcessAlive: (@Sendable (String, ProcessIdentity) -> Void)?

    public init(pollingInterval: TimeInterval = 2.0, gracePeriod: TimeInterval = 4.0) {
        self.pollingInterval = pollingInterval
        self.gracePeriod = gracePeriod
    }

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pollingInterval, repeating: pollingInterval)
        t.setEventHandler { [weak self] in
            self?.checkLiveness()
        }
        t.resume()
        timer = t
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        timer?.cancel()
        timer = nil
    }

    public func track(taskId: String, process: ProcessIdentity) {
        lock.lock()
        defer { lock.unlock() }
        tracked[taskId] = TrackedBinding(taskId: taskId, process: process, firstMissingAt: nil)
        if timer == nil {
            start()
        }
    }

    public func untrack(taskId: String) {
        lock.lock()
        defer { lock.unlock() }
        tracked.removeValue(forKey: taskId)
    }

    public func checkLiveness() {
        lock.lock()
        let currentTracked = tracked
        lock.unlock()

        let now = Date()
        var lostTasks: [(String, ProcessIdentity)] = []

        for (taskId, var item) in currentTracked {
            let isAlive = ProcessIdentityMatcher.isProcessAlive(item.process)
            if isAlive {
                if item.firstMissingAt != nil {
                    // Process recovered
                    item.firstMissingAt = nil
                    lock.lock()
                    tracked[taskId] = item
                    lock.unlock()
                }
                onProcessAlive?(taskId, item.process)
            } else {
                if let firstMissing = item.firstMissingAt {
                    let missingDuration = now.timeIntervalSince(firstMissing)
                    if missingDuration >= gracePeriod {
                        lostTasks.append((taskId, item.process))
                    }
                } else {
                    // First time detected missing
                    item.firstMissingAt = now
                    lock.lock()
                    tracked[taskId] = item
                    lock.unlock()
                }
            }
        }

        for (taskId, proc) in lostTasks {
            untrack(taskId: taskId)
            onProcessLost?(taskId, proc)
        }
    }
}
