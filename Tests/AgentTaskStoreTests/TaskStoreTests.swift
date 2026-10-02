import XCTest
@testable import AgentTaskCore
@testable import AgentTaskStore

final class TaskStoreTests: XCTestCase {
    var db: SQLiteDatabase!
    var store: TaskStore!

    override func setUpWithError() throws {
        // Use in-memory SQLite database for isolated tests
        db = try SQLiteDatabase(path: ":memory:")
        store = try TaskStore(database: db)
    }

    func testSessionCRUD() throws {
        let session = Session(
            id: "sess_1",
            agent: "claude",
            adapter: "claude-code",
            title: "Claude Code Run",
            startedAt: Date()
        )
        try store.upsertSession(session)

        let fetched = try store.fetchSession(id: "sess_1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.agent, "claude")
        XCTAssertEqual(fetched?.title, "Claude Code Run")

        let sessions = try store.fetchAllSessions()
        XCTAssertEqual(sessions.count, 1)

        // End session
        var ended = session
        ended.endedAt = Date()
        try store.upsertSession(ended)

        let fetchedEnded = try store.fetchSession(id: "sess_1")
        XCTAssertNotNil(fetchedEnded?.endedAt)
    }

    func testTaskHierarchyAndProgress() throws {
        let session = Session(id: "sess_2", agent: "cli", adapter: "cli")
        try store.upsertSession(session)

        let parent = Task(
            id: "root_task",
            sessionId: "sess_2",
            title: "Train GEFI M2",
            state: .running,
            projectName: "GEFI",
            projectPath: "/Users/gary/dev/gefi"
        )
        try store.upsertTask(parent)

        let child1 = Task(
            id: "child_1",
            sessionId: "sess_2",
            parentTaskId: "root_task",
            title: "Build dataset",
            state: .succeeded
        )
        try store.upsertTask(child1)

        let child2 = Task(
            id: "child_2",
            sessionId: "sess_2",
            parentTaskId: "root_task",
            title: "Train 800 steps",
            state: .running,
            progress: TaskProgress(fraction: 0.63, completedUnits: 504, totalUnits: 800, message: "step 504")
        )
        try store.upsertTask(child2)

        let fetchedParent = try store.fetchTask(id: "root_task")
        XCTAssertNotNil(fetchedParent)
        XCTAssertEqual(fetchedParent?.subtasks.count, 2)
        XCTAssertEqual(fetchedParent?.subtasks[0].title, "Build dataset")
        XCTAssertEqual(fetchedParent?.subtasks[1].progress?.percentageText, "63%")
    }

    func testEventDeduplication() throws {
        let eventId = "evt_unique_1"
        XCTAssertFalse(try store.isEventProcessed(eventId: eventId))

        try store.recordEvent(
            eventId: eventId,
            taskId: "t1",
            sessionId: "s1",
            eventType: "task.started",
            timestamp: Date(),
            sourceAdapter: "cli",
            payloadJSON: "{}"
        )

        XCTAssertTrue(try store.isEventProcessed(eventId: eventId))
    }
}
