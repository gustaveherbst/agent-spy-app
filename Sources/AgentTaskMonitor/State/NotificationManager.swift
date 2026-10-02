import Foundation
import UserNotifications
import AgentTaskCore

public final class NotificationManager: @unchecked Sendable {
    public static let shared = NotificationManager()
    private var isAuthorized = false

    private init() {
        requestAuthorization()
    }

    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            self.isAuthorized = granted
        }
    }

    public func notifyAttention(for task: Task) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Agent Needs Attention: \(task.title)"
        content.body = task.terminalReason ?? task.detail ?? "Task is waiting for developer input"
        content.sound = .default

        let req = UNNotificationRequest(identifier: "attn_\(task.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    public func notifyFailure(for task: Task) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Task Failed: \(task.title)"
        content.body = task.terminalReason ?? "The task exited with an error"
        content.sound = .defaultCritical

        let req = UNNotificationRequest(identifier: "fail_\(task.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    public func notifyCompletion(for task: Task) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Task Succeeded: \(task.title)"
        content.body = "Completed in \(task.formattedDuration())"
        content.sound = .default

        let req = UNNotificationRequest(identifier: "succ_\(task.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
