import Foundation
import SQLite3
import AgentTaskCore

public final class TaskStore: @unchecked Sendable {
    public let database: SQLiteDatabase

    public init(database: SQLiteDatabase) throws {
        self.database = database
        try DatabaseSchema.migrate(database)
    }

    /// Convenience initializer using default database location or environment override.
    public static func `default`() throws -> TaskStore {
        let path: String
        if let envPath = ProcessInfo.processInfo.environment["AGENTTASK_DB_PATH"], !envPath.isEmpty {
            path = envPath
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("AgentTask", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            path = dir.appendingPathComponent("agenttask.db").path
        }
        let db = try SQLiteDatabase(path: path)
        return try TaskStore(database: db)
    }

    // MARK: - Sessions

    public func upsertSession(_ session: Session) throws {
        let sql = """
        INSERT INTO sessions (id, agent, adapter, title, started_at, ended_at, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            agent = excluded.agent,
            adapter = excluded.adapter,
            title = excluded.title,
            ended_at = excluded.ended_at,
            metadata_json = excluded.metadata_json;
        """

        try database.withStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, (session.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (session.agent as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (session.adapter as NSString).utf8String, -1, nil)
            if let t = session.title {
                sqlite3_bind_text(stmt, 4, (t as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_bind_text(stmt, 5, (ATPIdentifiers.formatDate(session.startedAt) as NSString).utf8String, -1, nil)
            if let e = session.endedAt {
                sqlite3_bind_text(stmt, 6, (ATPIdentifiers.formatDate(e) as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            if let meta = session.metadata, let data = try? JSONEncoder().encode(meta), let str = String(data: data, encoding: .utf8) {
                sqlite3_bind_text(stmt, 7, (str as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 7)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw SQLiteError.stepFailed("Failed to upsert session \(session.id)")
            }
        }
    }

    public func fetchSession(id: String) throws -> Session? {
        let sql = "SELECT id, agent, adapter, title, started_at, ended_at, metadata_json FROM sessions WHERE id = ?;"
        return try database.withStatement(sql) { stmt -> Session? in
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return parseSessionRow(stmt)
            }
            return nil
        }
    }

    public func fetchAllSessions() throws -> [Session] {
        let sql = "SELECT id, agent, adapter, title, started_at, ended_at, metadata_json FROM sessions ORDER BY started_at DESC;"
        return try database.withStatement(sql) { stmt -> [Session] in
            var sessions: [Session] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let s = parseSessionRow(stmt) {
                    sessions.append(s)
                }
            }
            return sessions
        }
    }

    // MARK: - Tasks

    public func upsertTask(_ task: Task) throws {
        try database.transaction {
            let sql = """
            INSERT INTO tasks (
                id, session_id, parent_task_id, title, detail, state,
                project_name, project_path,
                progress_fraction, progress_completed, progress_total, progress_message,
                attention, started_at, updated_at, ended_at, terminal_reason, metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                session_id = excluded.session_id,
                parent_task_id = excluded.parent_task_id,
                title = excluded.title,
                detail = excluded.detail,
                state = excluded.state,
                project_name = excluded.project_name,
                project_path = excluded.project_path,
                progress_fraction = excluded.progress_fraction,
                progress_completed = excluded.progress_completed,
                progress_total = excluded.progress_total,
                progress_message = excluded.progress_message,
                attention = excluded.attention,
                started_at = excluded.started_at,
                updated_at = excluded.updated_at,
                ended_at = excluded.ended_at,
                terminal_reason = excluded.terminal_reason,
                metadata_json = excluded.metadata_json;
            """

            try database.withStatement(sql) { stmt in
                sqlite3_bind_text(stmt, 1, (task.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (task.sessionId as NSString).utf8String, -1, nil)

                if let pid = task.parentTaskId {
                    sqlite3_bind_text(stmt, 3, (pid as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }

                sqlite3_bind_text(stmt, 4, (task.title as NSString).utf8String, -1, nil)

                if let det = task.detail {
                    sqlite3_bind_text(stmt, 5, (det as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }

                sqlite3_bind_text(stmt, 6, (task.state.rawValue as NSString).utf8String, -1, nil)

                if let pn = task.projectName {
                    sqlite3_bind_text(stmt, 7, (pn as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }

                if let pp = task.projectPath {
                    sqlite3_bind_text(stmt, 8, (pp as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 8)
                }

                if let f = task.progress?.fraction {
                    sqlite3_bind_double(stmt, 9, f)
                } else {
                    sqlite3_bind_null(stmt, 9)
                }

                if let c = task.progress?.completedUnits {
                    sqlite3_bind_double(stmt, 10, c)
                } else {
                    sqlite3_bind_null(stmt, 10)
                }

                if let t = task.progress?.totalUnits {
                    sqlite3_bind_double(stmt, 11, t)
                } else {
                    sqlite3_bind_null(stmt, 11)
                }

                if let m = task.progress?.message {
                    sqlite3_bind_text(stmt, 12, (m as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 12)
                }

                sqlite3_bind_int(stmt, 13, task.attention ? 1 : 0)

                if let start = task.startedAt {
                    sqlite3_bind_text(stmt, 14, (ATPIdentifiers.formatDate(start) as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 14)
                }

                sqlite3_bind_text(stmt, 15, (ATPIdentifiers.formatDate(task.updatedAt) as NSString).utf8String, -1, nil)

                if let end = task.endedAt {
                    sqlite3_bind_text(stmt, 16, (ATPIdentifiers.formatDate(end) as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 16)
                }

                if let reason = task.terminalReason {
                    sqlite3_bind_text(stmt, 17, (reason as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 17)
                }

                if let meta = task.metadata, let data = try? JSONEncoder().encode(meta), let str = String(data: data, encoding: .utf8) {
                    sqlite3_bind_text(stmt, 18, (str as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 18)
                }

                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw SQLiteError.stepFailed("Failed to upsert task \(task.id)")
                }
            }

            // Upsert process binding if present
            if let proc = task.process {
                try upsertProcessBinding(taskId: task.id, process: proc)
            }

            // Upsert actions if present
            if !task.actions.isEmpty {
                try upsertActions(taskId: task.id, actions: task.actions)
            }
        }
    }

    public func fetchTask(id: String) throws -> Task? {
        let sql = """
        SELECT
            id, session_id, parent_task_id, title, detail, state,
            project_name, project_path,
            progress_fraction, progress_completed, progress_total, progress_message,
            attention, started_at, updated_at, ended_at, terminal_reason, metadata_json
        FROM tasks WHERE id = ?;
        """
        guard var task = try database.withStatement(sql, { stmt -> Task? in
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return parseTaskRow(stmt)
            }
            return nil
        }) else {
            return nil
        }

        task.process = try fetchProcessBinding(taskId: id)
        task.actions = try fetchActions(taskId: id)
        task.subtasks = try fetchChildTasks(parentTaskId: id)
        return task
    }

    public func fetchActiveTasks() throws -> [Task] {
        let sql = """
        SELECT
            id, session_id, parent_task_id, title, detail, state,
            project_name, project_path,
            progress_fraction, progress_completed, progress_total, progress_message,
            attention, started_at, updated_at, ended_at, terminal_reason, metadata_json
        FROM tasks
        WHERE state IN ('running', 'queued', 'waiting', 'blocked', 'registered')
        ORDER BY updated_at DESC;
        """
        return try fetchTasksWithSubtasks(querySQL: sql)
    }

    public func fetchRecentlyCompletedTasks(limit: Int = 50) throws -> [Task] {
        let sql = """
        SELECT
            id, session_id, parent_task_id, title, detail, state,
            project_name, project_path,
            progress_fraction, progress_completed, progress_total, progress_message,
            attention, started_at, updated_at, ended_at, terminal_reason, metadata_json
        FROM tasks
        WHERE state IN ('succeeded', 'failed', 'cancelled', 'aborted')
        ORDER BY updated_at DESC
        LIMIT \(limit);
        """
        return try fetchTasksWithSubtasks(querySQL: sql)
    }

    public func fetchAllTasks() throws -> [Task] {
        let sql = """
        SELECT
            id, session_id, parent_task_id, title, detail, state,
            project_name, project_path,
            progress_fraction, progress_completed, progress_total, progress_message,
            attention, started_at, updated_at, ended_at, terminal_reason, metadata_json
        FROM tasks
        ORDER BY updated_at DESC;
        """
        return try fetchTasksWithSubtasks(querySQL: sql)
    }

    public func fetchChildTasks(parentTaskId: String) throws -> [Task] {
        let sql = """
        SELECT
            id, session_id, parent_task_id, title, detail, state,
            project_name, project_path,
            progress_fraction, progress_completed, progress_total, progress_message,
            attention, started_at, updated_at, ended_at, terminal_reason, metadata_json
        FROM tasks
        WHERE parent_task_id = ?
        ORDER BY started_at ASC, updated_at ASC;
        """
        let flatChildren = try database.withStatement(sql) { stmt -> [Task] in
            sqlite3_bind_text(stmt, 1, (parentTaskId as NSString).utf8String, -1, nil)
            var children: [Task] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let child = parseTaskRow(stmt) {
                    children.append(child)
                }
            }
            return children
        }

        var enriched: [Task] = []
        for var child in flatChildren {
            child.process = try? fetchProcessBinding(taskId: child.id)
            child.actions = (try? fetchActions(taskId: child.id)) ?? []
            child.subtasks = (try? fetchChildTasks(parentTaskId: child.id)) ?? []
            enriched.append(child)
        }
        return enriched
    }

    private func fetchTasksWithSubtasks(querySQL: String) throws -> [Task] {
        let flatTasks = try database.withStatement(querySQL) { stmt -> [Task] in
            var tasks: [Task] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let t = parseTaskRow(stmt) {
                    tasks.append(t)
                }
            }
            return tasks
        }

        // Attach processes, actions, and nested child tasks
        var enriched: [Task] = []
        for var task in flatTasks {
            task.process = try? fetchProcessBinding(taskId: task.id)
            task.actions = (try? fetchActions(taskId: task.id)) ?? []
            task.subtasks = (try? fetchChildTasks(parentTaskId: task.id)) ?? []
            enriched.append(task)
        }
        return enriched
    }

    public func deleteOldTasks(retentionCount: Int) throws {
        // Keeps only the most recent `retentionCount` completed tasks
        let sql = """
        DELETE FROM tasks
        WHERE state IN ('succeeded', 'failed', 'cancelled', 'aborted')
        AND id NOT IN (
            SELECT id FROM tasks
            WHERE state IN ('succeeded', 'failed', 'cancelled', 'aborted')
            ORDER BY updated_at DESC
            LIMIT ?
        );
        """
        try database.withStatement(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(retentionCount))
            _ = sqlite3_step(stmt)
        }
    }

    // MARK: - Process Bindings

    public func upsertProcessBinding(taskId: String, process: ProcessIdentity) throws {
        let sql = """
        INSERT INTO process_bindings (task_id, pid, ppid, process_started_at, executable, bundle_id, cwd, last_alive_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(task_id) DO UPDATE SET
            pid = excluded.pid,
            ppid = excluded.ppid,
            process_started_at = excluded.process_started_at,
            executable = excluded.executable,
            bundle_id = excluded.bundle_id,
            cwd = excluded.cwd,
            last_alive_at = excluded.last_alive_at;
        """
        try database.withStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, (taskId as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, process.pid)
            if let ppid = process.ppid {
                sqlite3_bind_int(stmt, 3, ppid)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            if let start = process.processStartedAt {
                sqlite3_bind_text(stmt, 4, (ATPIdentifiers.formatDate(start) as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            if let exe = process.executable {
                sqlite3_bind_text(stmt, 5, (exe as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            if let bundle = process.bundleId {
                sqlite3_bind_text(stmt, 6, (bundle as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            if let cwd = process.cwd {
                sqlite3_bind_text(stmt, 7, (cwd as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            if let alive = process.lastAliveAt {
                sqlite3_bind_text(stmt, 8, (ATPIdentifiers.formatDate(alive) as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 8)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw SQLiteError.stepFailed("Failed to upsert process binding for task \(taskId)")
            }
        }
    }

    public func fetchProcessBinding(taskId: String) throws -> ProcessIdentity? {
        let sql = "SELECT pid, ppid, process_started_at, executable, bundle_id, cwd, last_alive_at FROM process_bindings WHERE task_id = ?;"
        return try database.withStatement(sql) { stmt -> ProcessIdentity? in
            sqlite3_bind_text(stmt, 1, (taskId as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let pid = sqlite3_column_int(stmt, 0)
                let ppid = sqlite3_column_type(stmt, 1) != SQLITE_NULL ? sqlite3_column_int(stmt, 1) : nil
                var startAt: Date?
                if let s = sqlite3_column_text(stmt, 2) {
                    startAt = ATPIdentifiers.parseDate(String(cString: s))
                }
                let exe = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                let bundle = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                let cwd = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
                var lastAlive: Date?
                if let l = sqlite3_column_text(stmt, 6) {
                    lastAlive = ATPIdentifiers.parseDate(String(cString: l))
                }
                return ProcessIdentity(
                    pid: pid,
                    ppid: ppid,
                    processStartedAt: startAt,
                    executable: exe,
                    bundleId: bundle,
                    cwd: cwd,
                    lastAliveAt: lastAlive
                )
            }
            return nil
        }
    }

    // MARK: - Actions

    public func upsertActions(taskId: String, actions: [TaskAction]) throws {
        let deleteSql = "DELETE FROM task_actions WHERE task_id = ?;"
        try database.withStatement(deleteSql) { stmt in
            sqlite3_bind_text(stmt, 1, (taskId as NSString).utf8String, -1, nil)
            _ = sqlite3_step(stmt)
        }

        let insertSql = "INSERT INTO task_actions (task_id, action_id, label, kind, payload_json) VALUES (?, ?, ?, ?, ?);"
        for action in actions {
            try database.withStatement(insertSql) { stmt in
                sqlite3_bind_text(stmt, 1, (taskId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (action.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (action.label as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (action.kind as NSString).utf8String, -1, nil)

                if let p = action.payload, let data = try? JSONEncoder().encode(p), let str = String(data: data, encoding: .utf8) {
                    sqlite3_bind_text(stmt, 5, (str as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_text(stmt, 5, "{}", -1, nil)
                }

                _ = sqlite3_step(stmt)
            }
        }
    }

    public func fetchActions(taskId: String) throws -> [TaskAction] {
        let sql = "SELECT action_id, label, kind, payload_json FROM task_actions WHERE task_id = ?;"
        return try database.withStatement(sql) { stmt -> [TaskAction] in
            sqlite3_bind_text(stmt, 1, (taskId as NSString).utf8String, -1, nil)
            var actions: [TaskAction] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idStr = sqlite3_column_text(stmt, 0),
                      let labelStr = sqlite3_column_text(stmt, 1),
                      let kindStr = sqlite3_column_text(stmt, 2) else { continue }
                var payload: [String: String]?
                if let pStr = sqlite3_column_text(stmt, 3) {
                    let json = String(cString: pStr)
                    if let data = json.data(using: .utf8) {
                        payload = try? JSONDecoder().decode([String: String].self, from: data)
                    }
                }
                actions.append(TaskAction(
                    id: String(cString: idStr),
                    label: String(cString: labelStr),
                    kind: String(cString: kindStr),
                    payload: payload
                ))
            }
            return actions
        }
    }

    // MARK: - Task Events (Deduplication & Audit)

    public func isEventProcessed(eventId: String) throws -> Bool {
        let sql = "SELECT 1 FROM task_events WHERE event_id = ?;"
        return try database.withStatement(sql) { stmt -> Bool in
            sqlite3_bind_text(stmt, 1, (eventId as NSString).utf8String, -1, nil)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    public func recordEvent(
        eventId: String,
        taskId: String?,
        sessionId: String?,
        eventType: String,
        timestamp: Date,
        sourceAdapter: String,
        payloadJSON: String
    ) throws {
        let sql = """
        INSERT INTO task_events (event_id, task_id, session_id, event_type, timestamp, source_adapter, payload_json)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        try database.withStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, (eventId as NSString).utf8String, -1, nil)
            if let t = taskId {
                sqlite3_bind_text(stmt, 2, (t as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            if let s = sessionId {
                sqlite3_bind_text(stmt, 3, (s as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, (eventType as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (ATPIdentifiers.formatDate(timestamp) as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (sourceAdapter as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 7, (payloadJSON as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                throw SQLiteError.stepFailed("Failed to record event \(eventId)")
            }
        }
    }
}

// MARK: - Row Parsers

private func parseSessionRow(_ stmt: OpaquePointer) -> Session? {
    guard let idStr = sqlite3_column_text(stmt, 0),
          let agentStr = sqlite3_column_text(stmt, 1),
          let adapterStr = sqlite3_column_text(stmt, 2),
          let startStr = sqlite3_column_text(stmt, 4) else { return nil }

    let id = String(cString: idStr)
    let agent = String(cString: agentStr)
    let adapter = String(cString: adapterStr)
    let title = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
    guard let startedAt = ATPIdentifiers.parseDate(String(cString: startStr)) else { return nil }

    var endedAt: Date?
    if let endStr = sqlite3_column_text(stmt, 5) {
        endedAt = ATPIdentifiers.parseDate(String(cString: endStr))
    }

    var metadata: [String: String]?
    if let metaStr = sqlite3_column_text(stmt, 6) {
        let json = String(cString: metaStr)
        if let data = json.data(using: .utf8) {
            metadata = try? JSONDecoder().decode([String: String].self, from: data)
        }
    }

    return Session(id: id, agent: agent, adapter: adapter, title: title, startedAt: startedAt, endedAt: endedAt, metadata: metadata)
}

private func parseTaskRow(_ stmt: OpaquePointer) -> Task? {
    guard let idStr = sqlite3_column_text(stmt, 0),
          let sessionStr = sqlite3_column_text(stmt, 1),
          let titleStr = sqlite3_column_text(stmt, 3),
          let stateStr = sqlite3_column_text(stmt, 5),
          let updateStr = sqlite3_column_text(stmt, 14) else { return nil }

    let id = String(cString: idStr)
    let sessionId = String(cString: sessionStr)
    let parentTaskId = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
    let title = String(cString: titleStr)
    let detail = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
    let state = TaskState(rawValue: String(cString: stateStr)) ?? .unknown

    let projectName = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
    let projectPath = sqlite3_column_text(stmt, 7).map { String(cString: $0) }

    var fraction: Double?
    if sqlite3_column_type(stmt, 8) != SQLITE_NULL {
        fraction = sqlite3_column_double(stmt, 8)
    }
    var completed: Double?
    if sqlite3_column_type(stmt, 9) != SQLITE_NULL {
        completed = sqlite3_column_double(stmt, 9)
    }
    var total: Double?
    if sqlite3_column_type(stmt, 10) != SQLITE_NULL {
        total = sqlite3_column_double(stmt, 10)
    }
    let message = sqlite3_column_text(stmt, 11).map { String(cString: $0) }

    var progress: TaskProgress?
    if fraction != nil || completed != nil || total != nil || message != nil {
        progress = TaskProgress(fraction: fraction, completedUnits: completed, totalUnits: total, message: message)
    }

    let attention = sqlite3_column_int(stmt, 12) == 1

    var startedAt: Date?
    if let startStr = sqlite3_column_text(stmt, 13) {
        startedAt = ATPIdentifiers.parseDate(String(cString: startStr))
    }

    guard let updatedAt = ATPIdentifiers.parseDate(String(cString: updateStr)) else { return nil }

    var endedAt: Date?
    if let endStr = sqlite3_column_text(stmt, 15) {
        endedAt = ATPIdentifiers.parseDate(String(cString: endStr))
    }

    let terminalReason = sqlite3_column_text(stmt, 16).map { String(cString: $0) }

    var metadata: [String: String]?
    if let metaStr = sqlite3_column_text(stmt, 17) {
        let json = String(cString: metaStr)
        if let data = json.data(using: .utf8) {
            metadata = try? JSONDecoder().decode([String: String].self, from: data)
        }
    }

    return Task(
        id: id,
        sessionId: sessionId,
        parentTaskId: parentTaskId,
        title: title,
        detail: detail,
        state: state,
        projectName: projectName,
        projectPath: projectPath,
        progress: progress,
        attention: attention,
        startedAt: startedAt,
        updatedAt: updatedAt,
        endedAt: endedAt,
        terminalReason: terminalReason,
        metadata: metadata
    )
}
