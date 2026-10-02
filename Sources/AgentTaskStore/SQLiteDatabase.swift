import Foundation
import SQLite3
import AgentTaskCore

public enum SQLiteError: Error, CustomStringConvertible, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case executeFailed(String)
    case bindFailed(String)
    case busy

    public var description: String {
        switch self {
        case .openFailed(let m): return "SQLite open failed: \(m)"
        case .prepareFailed(let m): return "SQLite prepare failed: \(m)"
        case .stepFailed(let m): return "SQLite step failed: \(m)"
        case .executeFailed(let m): return "SQLite execute failed: \(m)"
        case .bindFailed(let m): return "SQLite bind failed: \(m)"
        case .busy: return "SQLite database busy"
        }
    }
}

/// Thread-safe SQLite database connection wrapper.
public final class SQLiteDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    public let path: String

    public init(path: String) throws {
        self.path = path
        let fileManager = FileManager.default

        // If path is not memory, create parent directory
        if path != ":memory:" {
            let directory = (path as NSString).deletingLastPathComponent
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let dbHandle = handle else {
            let err = handle != nil ? String(cString: sqlite3_errmsg(handle)) : "Unknown"
            if let h = handle { sqlite3_close(h) }
            throw SQLiteError.openFailed(err)
        }
        self.db = dbHandle

        // Configure WAL mode, foreign keys, and busy timeout
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try execute("PRAGMA busy_timeout=5000;")
    }

    deinit {
        lock.lock()
        if let db = db {
            sqlite3_close(db)
        }
        lock.unlock()
    }

    public func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let db = db else { throw SQLiteError.executeFailed("Database closed") }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg != nil ? String(cString: errMsg!) : String(cString: sqlite3_errmsg(db))
            sqlite3_free(errMsg)
            throw SQLiteError.executeFailed(msg)
        }
    }

    public func transaction<T>(_ block: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try block()
            try execute("COMMIT TRANSACTION;")
            return result
        } catch {
            try? execute("ROLLBACK TRANSACTION;")
            throw error
        }
    }

    public func withStatement<T>(_ sql: String, _ block: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        guard let db = db else { throw SQLiteError.prepareFailed("Database closed") }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed("\(msg) for query: \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        return try block(statement)
    }
}
