import XCTest
@testable import AgentTaskCore
@testable import AgentTaskProcess

final class ProcessInspectionTests: XCTestCase {
    func testCurrentProcessInspection() {
        let current = ProcessInspector.currentProcess()
        XCTAssertEqual(current.pid, getpid())
        XCTAssertNotNil(current.processStartedAt)
        XCTAssertNotNil(current.executable)
        XCTAssertTrue(ProcessIdentityMatcher.isProcessAlive(current))
    }

    func testDeadProcessDetection() {
        // PID 999999 almost certainly does not exist
        let fake = ProcessIdentity(pid: 999999, processStartedAt: Date())
        XCTAssertFalse(ProcessIdentityMatcher.isProcessAlive(fake))
    }

    func testPIDReuseDetection() {
        // Check if start time mismatch detects PID recycling
        let myPid = getpid()
        // Provide a fake start timestamp 10 hours ago
        let fakeStart = Date().addingTimeInterval(-36000)
        let recycledIdentity = ProcessIdentity(pid: myPid, processStartedAt: fakeStart)
        XCTAssertFalse(ProcessIdentityMatcher.isProcessAlive(recycledIdentity))
    }
}
