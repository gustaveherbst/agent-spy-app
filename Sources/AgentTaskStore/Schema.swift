import Foundation

public enum DatabaseSchema {
    public static let createTablesSQL = """
    PRAGMA foreign_keys=ON;

    CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        agent TEXT NOT NULL,
        adapter TEXT NOT NULL,
        title TEXT,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        metadata_json TEXT
    );

    CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        parent_task_id TEXT,
        title TEXT NOT NULL,
        detail TEXT,
        state TEXT NOT NULL,
        project_name TEXT,
        project_path TEXT,
        progress_fraction REAL,
        progress_completed REAL,
        progress_total REAL,
        progress_message TEXT,
        attention INTEGER NOT NULL DEFAULT 0,
        started_at TEXT,
        updated_at TEXT NOT NULL,
        ended_at TEXT,
        terminal_reason TEXT,
        metadata_json TEXT,
        FOREIGN KEY(session_id) REFERENCES sessions(id),
        FOREIGN KEY(parent_task_id) REFERENCES tasks(id)
    );

    CREATE INDEX IF NOT EXISTS idx_tasks_state ON tasks(state);
    CREATE INDEX IF NOT EXISTS idx_tasks_session ON tasks(session_id);
    CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks(parent_task_id);
    CREATE INDEX IF NOT EXISTS idx_tasks_updated ON tasks(updated_at);

    CREATE TABLE IF NOT EXISTS task_events (
        event_id TEXT PRIMARY KEY,
        task_id TEXT,
        session_id TEXT,
        event_type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        source_adapter TEXT NOT NULL,
        payload_json TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_events_task_time ON task_events(task_id, timestamp);

    CREATE TABLE IF NOT EXISTS process_bindings (
        task_id TEXT PRIMARY KEY,
        pid INTEGER NOT NULL,
        ppid INTEGER,
        process_started_at TEXT,
        executable TEXT,
        bundle_id TEXT,
        cwd TEXT,
        last_alive_at TEXT,
        FOREIGN KEY(task_id) REFERENCES tasks(id)
    );

    CREATE TABLE IF NOT EXISTS task_actions (
        task_id TEXT NOT NULL,
        action_id TEXT NOT NULL,
        label TEXT NOT NULL,
        kind TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY(task_id, action_id),
        FOREIGN KEY(task_id) REFERENCES tasks(id)
    );
    """

    public static func migrate(_ db: SQLiteDatabase) throws {
        try db.execute(createTablesSQL)
    }
}
