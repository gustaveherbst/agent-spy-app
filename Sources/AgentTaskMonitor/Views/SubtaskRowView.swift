import SwiftUI
import AgentTaskCore

public struct SubtaskRowView: View {
    public let subtask: Task
    public let isLast: Bool
    public let currentDate: Date

    public init(subtask: Task, isLast: Bool = false, currentDate: Date = Date()) {
        self.subtask = subtask
        self.isLast = isLast
        self.currentDate = currentDate
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Tree branch marker
            Text(isLast ? "└─" : "├─")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))

            // Status icon
            Image(systemName: subtask.state.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor(for: subtask.state))
                .frame(width: 14)

            // Subtask title
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(subtask.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    if let prog = subtask.progress {
                        if let pct = prog.percentageText {
                            Text(pct)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                        } else if let msg = prog.message {
                            Text(msg)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    } else if subtask.state.isActive {
                        Text(subtask.formattedDuration(at: currentDate))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Progress Bar if measurable
                if let prog = subtask.progress, let frac = prog.fraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(frac), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 2)
                }

                if let msg = subtask.progress?.message, subtask.progress?.fraction != nil {
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
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
