import SwiftUI
import AgentTaskCore

public struct HistoryView: View {
    @ObservedObject public var state: MonitorAppState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Task History")
                    .font(.headline)
                Spacer()
                Button("Clear History") {
                    state.clearHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()

            Divider()

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter history...", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // History List
            let historyTasks = filteredHistory
            if historyTasks.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No historical tasks")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(historyTasks) { task in
                            TaskRowView(
                                state: state,
                                task: task,
                                isExpanded: state.expandedTaskIds.contains(task.id)
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 580, height: 440)
    }

    private var filteredHistory: [Task] {
        let list = state.completedTasks
        if search.trimmingCharacters(in: .whitespaces).isEmpty {
            return list
        }
        let q = search.lowercased()
        return list.filter {
            $0.title.lowercased().contains(q) ||
            ($0.projectName?.lowercased().contains(q) ?? false) ||
            $0.state.displayName.lowercased().contains(q)
        }
    }
}
