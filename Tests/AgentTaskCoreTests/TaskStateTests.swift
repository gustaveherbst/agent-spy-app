import XCTest
@testable import AgentTaskCore

final class TaskStateTests: XCTestCase {
    func testStateProperties() {
        XCTAssertTrue(TaskState.running.isActive)
        XCTAssertTrue(TaskState.queued.isActive)
        XCTAssertTrue(TaskState.waiting.isActive)
        XCTAssertTrue(TaskState.blocked.isActive)

        XCTAssertFalse(TaskState.succeeded.isActive)
        XCTAssertFalse(TaskState.failed.isActive)
        XCTAssertFalse(TaskState.cancelled.isActive)
        XCTAssertFalse(TaskState.aborted.isActive)

        XCTAssertTrue(TaskState.succeeded.isTerminal)
        XCTAssertTrue(TaskState.failed.isTerminal)
        XCTAssertTrue(TaskState.cancelled.isTerminal)
        XCTAssertTrue(TaskState.aborted.isTerminal)

        XCTAssertFalse(TaskState.running.isTerminal)
        XCTAssertFalse(TaskState.waiting.isTerminal)

        XCTAssertTrue(TaskState.waiting.requiresAttention)
        XCTAssertTrue(TaskState.blocked.requiresAttention)
        XCTAssertFalse(TaskState.running.requiresAttention)
    }

    func testTransitions() {
        XCTAssertTrue(TaskState.registered.canTransition(to: .running))
        XCTAssertTrue(TaskState.running.canTransition(to: .waiting))
        XCTAssertTrue(TaskState.waiting.canTransition(to: .running))
        XCTAssertTrue(TaskState.running.canTransition(to: .succeeded))
        XCTAssertTrue(TaskState.running.canTransition(to: .aborted))

        // Terminal states cannot transition back to active
        XCTAssertFalse(TaskState.succeeded.canTransition(to: .running))
        XCTAssertFalse(TaskState.failed.canTransition(to: .waiting))
        XCTAssertFalse(TaskState.aborted.canTransition(to: .running))
    }

    func testProgress() {
        let p1 = TaskProgress(fraction: 0.63, completedUnits: 504, totalUnits: 800)
        XCTAssertEqual(p1.percentageText, "63%")
        XCTAssertTrue(p1.summaryText.contains("504"))

        let p2 = TaskProgress(fraction: nil, completedUnits: 10, totalUnits: 20)
        XCTAssertEqual(p2.fraction, 0.5)
        XCTAssertEqual(p2.percentageText, "50%")

        // Never clamp out-of-bounds to NaN
        let p3 = TaskProgress(fraction: 1.5)
        XCTAssertEqual(p3.fraction, 1.0)
    }

    func testDurationFormatting() {
        let task = Task(
            id: "task-1",
            sessionId: "s1",
            title: "Test",
            startedAt: Date().addingTimeInterval(-1123) // 18m 43s ago
        )
        let dur = task.formattedDuration()
        XCTAssertTrue(dur.contains("18m"), "Expected duration to contain 18m, got \(dur)")
    }
}
