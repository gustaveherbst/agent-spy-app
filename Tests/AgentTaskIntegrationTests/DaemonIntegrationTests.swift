import XCTest
@testable import AgentTaskCore
@testable import AgentTaskProtocol
@testable import AgentTaskStore
@testable import AgentTaskProcess
@testable import AgentTaskIPC
@testable import agenttaskd

final class DaemonIntegrationTests: XCTestCase {
    var tempSocketPath: String!
    var tempDbPath: String!
    var server: DaemonServer!
    var client: IPCSocketClient!

    override func setUpWithError() throws {
        let uuid = UUID().uuidString
        tempSocketPath = "/tmp/test_daemon_\(uuid).sock"
        tempDbPath = "/tmp/test_db_\(uuid).db"

        let db = try SQLiteDatabase(path: tempDbPath)
        let store = try TaskStore(database: db)

        server = try DaemonServer(
            socketPath: tempSocketPath,
            store: store,
            pollingInterval: 0.1,
            gracePeriod: 0.2
        )
        try server.start()

        client = IPCSocketClient(socketPath: tempSocketPath)
    }

    override func tearDown() {
        client.disconnect()
        server.stop()
        unlink(tempSocketPath)
        unlink(tempDbPath)
    }

    func testEndToEndLifecycle() async throws {
        try client.connect()

        // 1. Register Session
        let sessionEnv = ATPEnvelope(
            eventType: .sessionRegistered,
            source: ATPSource(adapter: "claude-code", agent: "claude"),
            sessionId: "sess_demo",
            payload: ATPPayload(title: "Demo Claude Session")
        )
        try await client.emitEvent(sessionEnv)

        // 2. Start Root Task
        let rootEnv = ATPEnvelope(
            eventType: .taskStarted,
            source: ATPSource(adapter: "claude-code", agent: "claude"),
            sessionId: "sess_demo",
            taskId: "task_root",
            payload: ATPPayload(title: "Train GEFI M2", project: ProjectInfo(name: "GEFI", path: "/Users/gary/dev/gefi"))
        )
        try await client.emitEvent(rootEnv)

        // 3. Start Subtask
        let subtaskEnv = ATPEnvelope(
            eventType: .taskStarted,
            source: ATPSource(adapter: "claude-code", agent: "claude"),
            sessionId: "sess_demo",
            taskId: "task_sub_1",
            parentTaskId: "task_root",
            payload: ATPPayload(title: "Train 800 steps", fraction: 0.63, completedUnits: 504, totalUnits: 800)
        )
        try await client.emitEvent(subtaskEnv)

        // 4. Verify snapshot
        let snap = try await client.getSnapshot()
        XCTAssertEqual(snap.sessions.count, 1)
        XCTAssertEqual(snap.activeTasks.count, 2)

        let rootTask = snap.tasks.first(where: { $0.id == "task_root" })
        XCTAssertNotNil(rootTask)
        XCTAssertEqual(rootTask?.title, "Train GEFI M2")
        XCTAssertEqual(rootTask?.subtasks.count, 1)
        XCTAssertEqual(rootTask?.subtasks.first?.progress?.percentageText, "63%")

        // 5. Mark waiting
        let waitingEnv = ATPEnvelope(
            eventType: .taskWaiting,
            source: ATPSource(adapter: "claude-code", agent: "claude"),
            sessionId: "sess_demo",
            taskId: "task_root",
            payload: ATPPayload(reason: "Waiting for user input", attention: true)
        )
        try await client.emitEvent(waitingEnv)

        let snapWaiting = try await client.getSnapshot()
        let waitingTask = snapWaiting.tasks.first(where: { $0.id == "task_root" })
        XCTAssertEqual(waitingTask?.state, .waiting)
        XCTAssertTrue(waitingTask?.attention == true)

        // 6. Complete task
        let doneEnv = ATPEnvelope(
            eventType: .taskSucceeded,
            source: ATPSource(adapter: "claude-code", agent: "claude"),
            sessionId: "sess_demo",
            taskId: "task_root"
        )
        try await client.emitEvent(doneEnv)

        let snapDone = try await client.getSnapshot()
        let doneTask = snapDone.tasks.first(where: { $0.id == "task_root" })
        XCTAssertEqual(doneTask?.state, .succeeded)
    }

    func testProcessLossReconciliation() async throws {
        try client.connect()

        // Register a task bound to a non-existent PID (e.g. 999999)
        let deadProc = ProcessIdentity(pid: 999999, processStartedAt: Date())
        let taskEnv = ATPEnvelope(
            eventType: .taskStarted,
            source: ATPSource(adapter: "cli", agent: "custom"),
            sessionId: "sess_proc",
            taskId: "task_bound_dead",
            payload: ATPPayload(title: "Dead Process Task", process: deadProc)
        )
        try await client.emitEvent(taskEnv)

        // Wait slightly longer than grace period (0.2s + polling 0.1s)
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // Force liveness check
        server.livenessMonitor.checkLiveness()

        let snap = try await client.getSnapshot()
        let task = snap.tasks.first(where: { $0.id == "task_bound_dead" })
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.state, .aborted)
        XCTAssertEqual(task?.terminalReason, "process_lost")
    }
}
