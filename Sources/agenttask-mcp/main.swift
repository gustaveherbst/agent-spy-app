import Foundation
import AgentTaskIPC
import AgentTaskAdapters

@main
struct AgentTaskMCPMain {
    static func main() async {
        let client = IPCSocketClient()
        let adapter = MCPAdapter(client: client)
        await adapter.runStdio()
    }
}
