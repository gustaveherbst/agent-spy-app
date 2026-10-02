import Foundation
import Darwin
import AgentTaskCore
import AgentTaskProtocol
import AgentTaskStore
import AgentTaskProcess
import AgentTaskIPC

var socketPath = IPCConstants.defaultSocketPath()
var dbPath: String?
var polling: Double = 2.0
var grace: Double = 4.0

let args = CommandLine.arguments
var i = 1
while i < args.count {
    switch args[i] {
    case "--socket":
        if i + 1 < args.count {
            socketPath = args[i + 1]
            i += 1
        }
    case "--db":
        if i + 1 < args.count {
            dbPath = args[i + 1]
            i += 1
        }
    case "--polling":
        if i + 1 < args.count, let p = Double(args[i + 1]) {
            polling = p
            i += 1
        }
    case "--grace":
        if i + 1 < args.count, let g = Double(args[i + 1]) {
            grace = g
            i += 1
        }
    case "--help", "-h":
        print("""
        Usage: agenttaskd [options]

        Options:
          --socket <path>     Unix domain socket path
          --db <path>         SQLite database path
          --polling <sec>     Process polling interval (default: 2.0s)
          --grace <sec>       Process loss grace interval (default: 4.0s)
          --help, -h          Show this help message
        """)
        exit(0)
    default:
        break
    }
    i += 1
}

do {
    let store: TaskStore
    if let dbP = dbPath {
        let db = try SQLiteDatabase(path: dbP)
        store = try TaskStore(database: db)
    } else {
        store = try TaskStore.default()
    }

    let server = try DaemonServer(
        socketPath: socketPath,
        store: store,
        pollingInterval: polling,
        gracePeriod: grace
    )

    // Handle signals for graceful shutdown
    signal(SIGINT) { _ in
        print("\nagenttaskd: Received SIGINT, shutting down...")
        exit(0)
    }
    signal(SIGTERM) { _ in
        print("\nagenttaskd: Received SIGTERM, shutting down...")
        exit(0)
    }

    try server.start()
    print("agenttaskd started successfully")
    print("  Socket: \(socketPath)")
    print("  Database: \(store.database.path)")
    fflush(stdout)

    dispatchMain()
} catch {
    fputs("Error starting agenttaskd: \(error.localizedDescription)\n", stderr)
    exit(1)
}
