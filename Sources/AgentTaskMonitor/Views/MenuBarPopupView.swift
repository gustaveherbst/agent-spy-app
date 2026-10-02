import SwiftUI
import AgentTaskCore

public struct MenuBarPopupView: View {
    @ObservedObject public var state: MonitorAppState
    @State private var isCompletedExpanded = false

    public init(state: MonitorAppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Agent Tasks")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)

                // Active count badge
                let activeCount = state.activeTasks.count
                if activeCount > 0 {
                    Text("\(activeCount) active")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(10)
                }

                // MCP Server Indicator (Clickable to jump directly to MCP settings)
                Button {
                    state.isPreferencesPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(state.mcpServerRunning ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(verbatim: state.mcpServerRunning ? "MCP:\(state.mcpServerPort)" : "MCP:off")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(state.mcpServerRunning ? Color.green.opacity(0.12) : Color.primary.opacity(0.06))
                    .foregroundColor(state.mcpServerRunning ? .green : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(state.mcpServerRunning ? "MCP Endpoint: http://127.0.0.1:\(state.mcpServerPort)/sse (Click to configure)" : "MCP Server Disabled (Click to enable)")

                Spacer()

                // Connection status dot
                Circle()
                    .fill(state.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .help(state.isConnected ? "Connected to agenttaskd" : "Daemon disconnected")

                // History button
                Button {
                    state.isHistoryPresented = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Task History")

                // Preferences button
                Button {
                    state.isPreferencesPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Preferences (⌘,)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Scrollable Content
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // 1. Attention Required Section
                    let attnTasks = state.attentionTasks
                    if !attnTasks.isEmpty {
                        AttentionSectionView(state: state, attentionTasks: attnTasks)
                    }

                    // 2. Active Tasks Section
                    if state.activeTasks.isEmpty && attnTasks.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text("No active agent work")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Tasks started via Claude, MCP, or the agenttask CLI will appear here live.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        switch state.preferences.groupingMode {
                        case .byAgent:
                            ForEach(state.tasksGroupedByAgent, id: \.agent) { group in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(group.agent)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(group.tasks.count)")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.top, 6)

                                    ForEach(group.tasks) { task in
                                        TaskRowView(
                                            state: state,
                                            task: task,
                                            isExpanded: state.expandedTaskIds.contains(task.id)
                                        )
                                    }
                                }
                            }

                        case .byProject:
                            ForEach(state.tasksGroupedByProject, id: \.project) { group in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(group.project.uppercased())
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(group.tasks.count)")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.top, 6)

                                    ForEach(group.tasks) { task in
                                        TaskRowView(
                                            state: state,
                                            task: task,
                                            isExpanded: state.expandedTaskIds.contains(task.id)
                                        )
                                    }
                                }
                            }

                        case .flat:
                            ForEach(state.activeRootTasks) { task in
                                TaskRowView(
                                    state: state,
                                    task: task,
                                    isExpanded: state.expandedTaskIds.contains(task.id)
                                )
                            }
                        }
                    }

                    // 3. Recently Completed Section
                    let recentCompleted = Array(state.completedTasks.prefix(5))
                    if !recentCompleted.isEmpty {
                        Divider()
                            .padding(.horizontal, 8)

                        DisclosureGroup(
                            isExpanded: $isCompletedExpanded,
                            content: {
                                VStack(spacing: 4) {
                                    ForEach(recentCompleted) { task in
                                        TaskRowView(
                                            state: state,
                                            task: task,
                                            isExpanded: state.expandedTaskIds.contains(task.id)
                                        )
                                    }
                                }
                                .padding(.top, 4)
                            },
                            label: {
                                HStack {
                                    Text("RECENTLY COMPLETED")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(recentCompleted.count)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        )
                        .padding(.horizontal, 10)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 520)

            Divider()

            // Footer Status Bar
            HStack {
                let waitingCount = state.attentionTasks.count
                let activeCount = state.activeTasks.count

                HStack(spacing: 4) {
                    if waitingCount > 0 {
                        Text("\(waitingCount) waiting")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Text("\(activeCount) active")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("History") {
                    state.isHistoryPresented = true
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button("Preferences") {
                    state.isPreferencesPresented = true
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Text("·")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.85))
                .help("Quit AgentSpy (⌘Q)")
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 660)
        .sheet(isPresented: $state.isHistoryPresented) {
            HistoryView(state: state)
        }
        .sheet(isPresented: $state.isPreferencesPresented) {
            PreferencesView(state: state)
        }
    }
}
