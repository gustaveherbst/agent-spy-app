import Foundation
import AgentTaskCore
import AgentTaskProtocol

/// Declares capabilities of an adapter.
public struct AdapterCapabilities: Codable, Sendable, Equatable {
    public var canDiscoverSession: Bool
    public var canReportTaskLifecycle: Bool
    public var canReportProgress: Bool
    public var canReportSubtasks: Bool
    public var canReportAttention: Bool
    public var canDeepLink: Bool
    public var canCancel: Bool

    public init(
        canDiscoverSession: Bool = false,
        canReportTaskLifecycle: Bool = false,
        canReportProgress: Bool = false,
        canReportSubtasks: Bool = false,
        canReportAttention: Bool = false,
        canDeepLink: Bool = false,
        canCancel: Bool = false
    ) {
        self.canDiscoverSession = canDiscoverSession
        self.canReportTaskLifecycle = canReportTaskLifecycle
        self.canReportProgress = canReportProgress
        self.canReportSubtasks = canReportSubtasks
        self.canReportAttention = canReportAttention
        self.canDeepLink = canDeepLink
        self.canCancel = canCancel
    }

    /// Full capability tier for advanced adapters.
    public static let full = AdapterCapabilities(
        canDiscoverSession: true,
        canReportTaskLifecycle: true,
        canReportProgress: true,
        canReportSubtasks: true,
        canReportAttention: true,
        canDeepLink: true,
        canCancel: true
    )
}

public protocol AgentAdapter: Sendable {
    var adapterId: String { get }
    var capabilities: AdapterCapabilities { get }
}
