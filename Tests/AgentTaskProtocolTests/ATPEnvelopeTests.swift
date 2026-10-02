import XCTest
@testable import AgentTaskCore
@testable import AgentTaskProtocol

final class ATPEnvelopeTests: XCTestCase {
    func testEnvelopeSerialization() throws {
        let envelope = ATPEnvelope(
            eventType: .taskStarted,
            source: ATPSource(adapter: "claude-code", adapterVersion: "1.0.0", agent: "claude"),
            sessionId: "session-123",
            taskId: "training-42",
            payload: ATPPayload(
                title: "Train GEFI model",
                project: ProjectInfo(name: "GEFI", path: "/Users/me/dev/gefi"),
                fraction: 0.63
            )
        )

        let json = try envelope.toJSONString()
        XCTAssertTrue(json.contains("\"atp/1\""))
        XCTAssertTrue(json.contains("\"task.started\""))
        XCTAssertTrue(json.contains("\"training-42\""))

        let decoded = try ATPEnvelope.fromJSONString(json)
        XCTAssertEqual(decoded.protocol, "atp/1")
        XCTAssertEqual(decoded.eventType, .taskStarted)
        XCTAssertEqual(decoded.taskId, "training-42")
        XCTAssertEqual(decoded.payload.title, "Train GEFI model")
        XCTAssertEqual(decoded.payload.fraction, 0.63)
    }

    func testValidatorCatchesErrors() {
        // Missing taskId for task.started
        let invalid1 = ATPEnvelope(
            eventType: .taskStarted,
            source: ATPSource(adapter: "cli", agent: "custom"),
            sessionId: "s1",
            taskId: nil
        )
        XCTAssertThrowsError(try ATPValidator.validate(invalid1))

        // Invalid fraction > 1.0
        let invalid2 = ATPEnvelope(
            eventType: .taskProgress,
            source: ATPSource(adapter: "cli", agent: "custom"),
            sessionId: "s1",
            taskId: "t1",
            payload: ATPPayload(fraction: 1.5)
        )
        XCTAssertThrowsError(try ATPValidator.validate(invalid2))

        // Valid envelope passes
        let valid = ATPEnvelope(
            eventType: .taskProgress,
            source: ATPSource(adapter: "cli", agent: "custom"),
            sessionId: "s1",
            taskId: "t1",
            payload: ATPPayload(fraction: 0.5)
        )
        XCTAssertNoThrow(try ATPValidator.validate(valid))
    }
}
