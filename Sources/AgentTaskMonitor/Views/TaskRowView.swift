import SwiftUI
import AgentTaskCore

public struct TaskRowView: View {
    @ObservedObject public var state: MonitorAppState
    public let task: Task
    public let isExpanded: Bool

    @State private var isHovering = false

    public init(state: MonitorAppState, task: Task, isExpanded: Bool) {
        self.state = state
        self.task = task
        self.isExpanded = isExpanded
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Main Root Row
            HStack(alignment: .center, spacing: 10) {
                // Status Glyph
                Image(systemName: task.state.symbolName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(statusColor(for: task.state))
                    .frame(width: 18)

                // Task Title and Project Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if let proj = task.projectName, !proj.isEmpty {
                            Text(proj)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        if let path = task.projectPath, !path.isEmpty {
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text(task.project.abbreviatedPath)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Running duration live text
                if task.state.isActive {
                    Text(task.formattedDuration(at: state.currentDate))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                } else if let end = task.endedAt, let start = task.startedAt {
                    let dur = Int(end.timeIntervalSince(start))
                    Text("\(dur)s")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Expand / Collapse Chevron if has subtasks
                if !task.subtasks.isEmpty {
                    Button {
                        state.toggleExpand(taskId: task.id)
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Waiting / Blocked Attention Callout
            if task.attention || task.state.requiresAttention {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(task.terminalReason ?? task.detail ?? "Waiting for input")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(4)
                .padding(.leading, 28)
            }

            // Subtasks Tree
            if isExpanded && !task.subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(task.subtasks.enumerated()), id: \.element.id) { index, subtask in
                        SubtaskRowView(
                            subtask: subtask,
                            isLast: index == task.subtasks.count - 1,
                            currentDate: state.currentDate
                        )
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            if task.projectPath != nil {
                Button("Reveal in Finder") {
                    state.revealInFinder(task: task)
                }
                Button("Open in Terminal") {
                    state.openInTerminal(task: task)
                }
                Divider()
            }
            Button("Copy Task Details") {
                state.copyTaskDetails(task: task)
            }
            Button("Copy Task ID") {
                state.copyTaskId(task: task)
            }
            if task.state.isActive {
                Divider()
                Button("Cancel Task", role: .destructive) {
                    state.cancelTask(task: task)
                }
            }
        }
    }

    private func statusColor(for state: TaskState) -> Color {
        switch state {
        case .running: return .blue
        case .succeeded: return .green
        case .waiting: return .orange
        case .blocked: return .red
        case .failed: return .red
        case .aborted: return .purple
        case .cancelled: return .secondary
        default: return .secondary
        }
    }
}
