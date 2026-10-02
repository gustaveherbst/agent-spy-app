import SwiftUI
import AppKit
import AgentTaskCore
import AgentTaskIPC

public struct PreferencesView: View {
    @ObservedObject public var state: MonitorAppState
    @Environment(\.dismiss) private var dismiss

    @State private var serverPort: Int = 8765
    @State private var portString: String = "8765"
    @State private var serverEnabled: Bool = true
    @State private var copyFeedbackText: String?

    public init(state: MonitorAppState) {
        self.state = state
        let port = state.preferences.mcpServerPort
        _serverPort = State(initialValue: port)
        _portString = State(initialValue: String(port))
        _serverEnabled = State(initialValue: state.preferences.mcpServerEnabled)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()

            Divider()

            Form {
                // MARK: - MCP Server Configuration
                Section("MCP Server (Model Context Protocol)") {
                    Toggle("Enable MCP Server", isOn: $serverEnabled)
                        .onChange(of: serverEnabled) { _, newValue in
                            state.setMCPServer(enabled: newValue, port: serverPort)
                        }

                    if serverEnabled {
                        HStack {
                            Text("Port")
                            Spacer()
                            TextField("Port", text: $portString)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 80)
                                .onChange(of: portString) { _, newValue in
                                    let filtered = newValue.filter { $0.isNumber }
                                    if filtered != newValue {
                                        portString = filtered
                                    }
                                    if let p = Int(filtered), (1...65535).contains(p) {
                                        serverPort = p
                                    }
                                }
                                .onSubmit {
                                    if let p = Int(portString), (1...65535).contains(p) {
                                        serverPort = p
                                        state.setMCPServer(enabled: serverEnabled, port: p)
                                    } else {
                                        portString = String(serverPort)
                                    }
                                }
                            Stepper("", value: $serverPort, in: 1024...65535, step: 1)
                                .labelsHidden()
                                .onChange(of: serverPort) { _, newPort in
                                    portString = String(newPort)
                                    state.setMCPServer(enabled: serverEnabled, port: newPort)
                                }
                            Button("Apply") {
                                if let p = Int(portString), (1...65535).contains(p) {
                                    serverPort = p
                                    state.setMCPServer(enabled: serverEnabled, port: p)
                                } else {
                                    portString = String(serverPort)
                                    state.setMCPServer(enabled: serverEnabled, port: serverPort)
                                }
                            }
                            .controlSize(.small)
                        }

                        // Live status indicator & Test button
                        HStack(spacing: 8) {
                            Circle()
                                .fill(state.mcpServerRunning ? Color.green : Color.red)
                                .frame(width: 8, height: 8)

                            if state.mcpServerRunning {
                                Text(verbatim: "Running on http://127.0.0.1:\(serverPort)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.green)
                                Spacer()
                                Button("Open Status") {
                                    if let url = URL(string: "http://127.0.0.1:\(serverPort)/status") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .controlSize(.mini)
                            } else if let err = state.mcpLastError {
                                Text("Failed: \(err)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            } else {
                                Text("Stopped")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Endpoints
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active Endpoints:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            HStack {
                                Text("SSE:")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 44, alignment: .leading)
                                Text(verbatim: "http://127.0.0.1:\(serverPort)/sse")
                                    .font(.system(size: 10, design: .monospaced))
                                Spacer()
                                Button("Copy") {
                                    copyToClipboard("http://127.0.0.1:\(serverPort)/sse")
                                    copyFeedbackText = "Copied SSE endpoint URL!"
                                }
                                .controlSize(.mini)
                            }

                            HStack {
                                Text("HTTP:")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 44, alignment: .leading)
                                Text(verbatim: "http://127.0.0.1:\(serverPort)/mcp")
                                    .font(.system(size: 10, design: .monospaced))
                                Spacer()
                                Button("Copy") {
                                    copyToClipboard("http://127.0.0.1:\(serverPort)/mcp")
                                    copyFeedbackText = "Copied HTTP endpoint URL!"
                                }
                                .controlSize(.mini)
                            }

                            HStack {
                                Text("Stdio:")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 44, alignment: .leading)
                                Text("/Applications/AgentSpy.app/Contents/MacOS/agenttask-mcp")
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Button("Copy") {
                                    copyToClipboard("/Applications/AgentSpy.app/Contents/MacOS/agenttask-mcp")
                                    copyFeedbackText = "Copied Stdio binary path!"
                                }
                                .controlSize(.mini)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)

                        // Client Setup Helper Buttons
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Add to Agent / Editor:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            HStack {
                                Button("Copy Claude Desktop JSON") {
                                    let json = """
                                    {
                                      "mcpServers": {
                                        "AgentSpy": {
                                          "url": "http://127.0.0.1:\(serverPort)/sse"
                                        }
                                      }
                                    }
                                    """
                                    copyToClipboard(json)
                                    copyFeedbackText = "Copied Claude Desktop configuration!"
                                }
                                .controlSize(.small)

                                Button("Copy Cursor / Windsurf SSE Config") {
                                    let json = """
                                    {
                                      "mcpServers": {
                                        "AgentSpy": {
                                          "url": "http://127.0.0.1:\(serverPort)/sse"
                                        }
                                      }
                                    }
                                    """
                                    copyToClipboard(json)
                                    copyFeedbackText = "Copied Cursor / Windsurf SSE configuration!"
                                }
                                .controlSize(.small)
                            }
                        }

                        if let feedback = copyFeedbackText {
                            Text(feedback)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                }

                // MARK: - General Settings
                Section("General") {
                    Toggle("Show active task count in menu bar", isOn: $state.preferences.showActiveCount)
                        .onChange(of: state.preferences.showActiveCount) { _, _ in
                            state.preferences.save()
                        }
                    Picker("Grouping Mode", selection: $state.preferences.groupingMode) {
                        ForEach(TaskGroupingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: state.preferences.groupingMode) { _, _ in
                        state.preferences.save()
                    }
                }

                // MARK: - Notifications
                Section("Notifications") {
                    Toggle("Notify when task needs attention", isOn: $state.preferences.notifyOnAttention)
                        .onChange(of: state.preferences.notifyOnAttention) { _, _ in state.preferences.save() }
                    Toggle("Notify when task fails", isOn: $state.preferences.notifyOnFailure)
                        .onChange(of: state.preferences.notifyOnFailure) { _, _ in state.preferences.save() }
                    Toggle("Notify when root task completes", isOn: $state.preferences.notifyOnCompletion)
                        .onChange(of: state.preferences.notifyOnCompletion) { _, _ in state.preferences.save() }
                }

                // MARK: - History & Retention
                Section("History & Retention") {
                    Stepper("Keep last \(state.preferences.completedTaskRetention) completed tasks", value: $state.preferences.completedTaskRetention, in: 10...500, step: 10)
                        .onChange(of: state.preferences.completedTaskRetention) { _, _ in state.preferences.save() }
                }

                // MARK: - Diagnostics
                Section("Diagnostics") {
                    LabeledContent("Status", value: state.isConnected ? "Connected to agenttaskd" : "Disconnected")
                    LabeledContent("Socket Path", value: IPCConstants.defaultSocketPath())
                    LabeledContent("Active Tasks", value: "\(state.activeTasks.count)")
                    LabeledContent("Completed Tasks", value: "\(state.completedTasks.count)")
                }

                // MARK: - Application
                Section {
                    Button(role: .destructive) {
                        NSApp.terminate(nil)
                    } label: {
                        HStack {
                            Spacer()
                            Label("Quit AgentSpy", systemImage: "power")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)
        }
        .frame(width: 580, height: 600)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
