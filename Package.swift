// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentTaskMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Libraries
        .library(name: "AgentTaskCore", targets: ["AgentTaskCore"]),
        .library(name: "AgentTaskProtocol", targets: ["AgentTaskProtocol"]),
        .library(name: "AgentTaskStore", targets: ["AgentTaskStore"]),
        .library(name: "AgentTaskProcess", targets: ["AgentTaskProcess"]),
        .library(name: "AgentTaskIPC", targets: ["AgentTaskIPC"]),
        .library(name: "AgentTaskAdapters", targets: ["AgentTaskAdapters"]),
        // Executables
        .executable(name: "agenttaskd", targets: ["agenttaskd"]),
        .executable(name: "agenttask", targets: ["agenttask"]),
        .executable(name: "agenttask-mcp", targets: ["agenttask-mcp"]),
        .executable(name: "AgentTaskMonitor", targets: ["AgentTaskMonitor"])
    ],
    dependencies: [],
    targets: [
        // Core models
        .target(
            name: "AgentTaskCore",
            dependencies: [],
            path: "Sources/AgentTaskCore"
        ),
        // ATP protocol validator & envelope
        .target(
            name: "AgentTaskProtocol",
            dependencies: ["AgentTaskCore"],
            path: "Sources/AgentTaskProtocol"
        ),
        // SQLite persistence
        .target(
            name: "AgentTaskStore",
            dependencies: ["AgentTaskCore"],
            path: "Sources/AgentTaskStore",
            cSettings: [
                .define("SQLITE_ENABLE_WAL")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        // Process inspection and liveness
        .target(
            name: "AgentTaskProcess",
            dependencies: ["AgentTaskCore"],
            path: "Sources/AgentTaskProcess"
        ),
        // Unix domain socket IPC
        .target(
            name: "AgentTaskIPC",
            dependencies: ["AgentTaskCore", "AgentTaskProtocol"],
            path: "Sources/AgentTaskIPC"
        ),
        // Adapters
        .target(
            name: "AgentTaskAdapters",
            dependencies: ["AgentTaskCore", "AgentTaskProtocol", "AgentTaskIPC", "AgentTaskProcess"],
            path: "Sources/AgentTaskAdapters"
        ),
        // Daemon
        .executableTarget(
            name: "agenttaskd",
            dependencies: [
                "AgentTaskCore",
                "AgentTaskProtocol",
                "AgentTaskStore",
                "AgentTaskProcess",
                "AgentTaskIPC"
            ],
            path: "Sources/agenttaskd"
        ),
        // CLI
        .executableTarget(
            name: "agenttask",
            dependencies: [
                "AgentTaskCore",
                "AgentTaskProtocol",
                "AgentTaskIPC",
                "AgentTaskProcess",
                "AgentTaskAdapters"
            ],
            path: "Sources/agenttask"
        ),
        // Standalone MCP executable
        .executableTarget(
            name: "agenttask-mcp",
            dependencies: [
                "AgentTaskCore",
                "AgentTaskProtocol",
                "AgentTaskIPC",
                "AgentTaskAdapters"
            ],
            path: "Sources/agenttask-mcp"
        ),
        // Native macOS Menu Bar App
        .executableTarget(
            name: "AgentTaskMonitor",
            dependencies: [
                "AgentTaskCore",
                "AgentTaskProtocol",
                "AgentTaskIPC",
                "AgentTaskProcess",
                "AgentTaskStore",
                "AgentTaskAdapters"
            ],
            path: "Sources/AgentTaskMonitor"
        ),
        // Tests
        .testTarget(
            name: "AgentTaskCoreTests",
            dependencies: ["AgentTaskCore"],
            path: "Tests/AgentTaskCoreTests"
        ),
        .testTarget(
            name: "AgentTaskProtocolTests",
            dependencies: ["AgentTaskProtocol"],
            path: "Tests/AgentTaskProtocolTests"
        ),
        .testTarget(
            name: "AgentTaskStoreTests",
            dependencies: ["AgentTaskStore"],
            path: "Tests/AgentTaskStoreTests"
        ),
        .testTarget(
            name: "AgentTaskProcessTests",
            dependencies: ["AgentTaskProcess"],
            path: "Tests/AgentTaskProcessTests"
        ),
        .testTarget(
            name: "AgentTaskIPCTests",
            dependencies: ["AgentTaskIPC"],
            path: "Tests/AgentTaskIPCTests"
        ),
        .testTarget(
            name: "AgentTaskIntegrationTests",
            dependencies: [
                "AgentTaskCore",
                "AgentTaskProtocol",
                "AgentTaskStore",
                "AgentTaskProcess",
                "AgentTaskIPC",
                "agenttaskd"
            ],
            path: "Tests/AgentTaskIntegrationTests"
        )
    ]
)
