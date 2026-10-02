import XCTest
@testable import AgentTaskCore
@testable import AgentTaskProtocol
@testable import AgentTaskIPC

final class IPCTests: XCTestCase {
    var tempSocketPath: String!
    var server: IPCSocketServer!
    var client: IPCSocketClient!

    override func setUpWithError() throws {
        tempSocketPath = "/tmp/test_agenttask_\(UUID().uuidString).sock"
        server = IPCSocketServer(socketPath: tempSocketPath)
        try server.start()
        client = IPCSocketClient(socketPath: tempSocketPath)
    }

    override func tearDown() {
        client.disconnect()
        server.stop()
        unlink(tempSocketPath)
    }

    func testRequestResponse() async throws {
        let srv = server
        server.onRequest = { request, clientFd in
            if request.type == "ping" {
                srv?.send(IPCServerMessage.ok(replyTo: request.id), to: clientFd)
            }
        }

        try client.connect()
        XCTAssertTrue(client.connected)

        let req = IPCClientRequest(type: "ping")
        let resp = try await client.send(request: req)
        XCTAssertEqual(resp.status, "ok")
    }

    func testSubscriptionStreaming() async throws {
        let srv = server
        server.onRequest = { request, clientFd in
            if request.type == "subscribe" {
                srv?.send(IPCServerMessage.ok(replyTo: request.id), to: clientFd)
            }
        }

        try client.connect()
        let stream = client.subscribe()

        // Wait a moment for subscription to be registered
        try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        let testTask = Task(id: "stream_task", sessionId: "s1", title: "Stream Task", state: .running)
        server.broadcast(IPCServerMessage.taskUpdate(testTask))

        for await message in stream {
            if message.type == "task_update" {
                XCTAssertEqual(message.task?.id, "stream_task")
                break
            }
        }
    }
}
