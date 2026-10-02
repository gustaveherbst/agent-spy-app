import SwiftUI
import AgentTaskCore

public struct AttentionSectionView: View {
    @ObservedObject public var state: MonitorAppState
    public let attentionTasks: [Task]

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 11, weight: .bold))
                Text("NEEDS ATTENTION (\(attentionTasks.count))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            ForEach(attentionTasks) { task in
                TaskRowView(
                    state: state,
                    task: task,
                    isExpanded: state.expandedTaskIds.contains(task.id)
                )
            }
            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }
}
