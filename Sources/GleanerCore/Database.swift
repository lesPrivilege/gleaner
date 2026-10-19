import Foundation
import SQLite3

/// A small SQLite connection: execute statements, run parameterized writes, read rows.
/// Opened in serialized mode; callers keep writes on one queue.
public final class Database: @unchecked Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
    }

    public typealias Row = [String: Any]

    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        try open(path, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX)
        try execute("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;")
    }

    /// Opens the database at `path` to read only: SQLite refuses every write through it, and a
    /// missing file is not created. A reader of a WAL database may still keep SQLite's shared-memory
    /// index beside it; the database itself is never written.
    public init(readingAt path: String) throws {
        try open(path, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
        try execute("PRAGMA busy_timeout = 5000;")
    }

    private func open(_ path: String, _ flags: Int32) throws {
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            throw Failure(description: "cannot open \(path): \(String(cString: sqlite3_errmsg(handle)))")
        }
    }

    deinit { sqlite3_close(handle) }

    public func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    /// Returns how many rows the statement inserted, changed or deleted.
    @discardableResult
    public func run(_ sql: String, _ arguments: [Any?] = []) throws -> Int {
        let statement = try prepare(sql, arguments)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
        return Int(sqlite3_changes(handle))
    }

    public func rows(_ sql: String, _ arguments: [Any?] = []) throws -> [Row] {
        let statement = try prepare(sql, arguments)
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw failure() }
            var row: Row = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement, column)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, column)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, column))
                default: break
                }
            }
            rows.append(row)
        }
        return rows
    }

    @discardableResult
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ arguments: [Any?]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        for (offset, argument) in arguments.enumerated() {
            let index = Int32(offset + 1)
            switch argument {
            case nil: sqlite3_bind_null(statement, index)
            case let value as String: sqlite3_bind_text(statement, index, value, -1, Self.transient)
            case let value as Int: sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Int64: sqlite3_bind_int64(statement, index, value)
            case let value as Double: sqlite3_bind_double(statement, index, value)
            case let value as Date: sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
            default:
                sqlite3_finalize(statement)
                throw Failure(description: "unsupported argument \(String(describing: argument))")
            }
        }
        return statement
    }

    private func failure() -> Failure {
        Failure(description: String(cString: sqlite3_errmsg(handle)))
    }
}
