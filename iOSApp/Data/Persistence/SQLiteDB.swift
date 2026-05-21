import Foundation
import SQLite3

public final class SQLiteDB {
    private var db: OpaquePointer?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    public init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            let msg = db != nil ? String(cString: sqlite3_errmsg(db)) : "Unknown error"
            throw DatabaseError.openFailed(msg)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    public func execute(_ sql: String, arguments: [Any] = []) throws {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DatabaseError.prepareFailed(errorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        
        try bind(stmt!, arguments: arguments)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.executionFailed(errorMessage())
        }
    }
    
    public func query(_ sql: String, arguments: [Any] = []) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DatabaseError.prepareFailed(errorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        
        try bind(stmt!, arguments: arguments)
        
        var rows = [[String: Any]]()
        let colCount = sqlite3_column_count(stmt)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row = [String: Any]()
            for i in 0..<colCount {
                let colName = String(cString: sqlite3_column_name(stmt, i))
                let colType = sqlite3_column_type(stmt, i)
                switch colType {
                case SQLITE_INTEGER:
                    row[colName] = Int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    row[colName] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    if let ptr = sqlite3_column_text(stmt, i) {
                        row[colName] = String(cString: ptr)
                    } else {
                        row[colName] = ""
                    }
                case SQLITE_NULL:
                    row[colName] = NSNull()
                default:
                    row[colName] = NSNull()
                }
            }
            rows.append(row)
        }
        return rows
    }
    
    public func transaction<T>(_ block: () throws -> T) throws -> T {
        try execute("BEGIN TRANSACTION;")
        do {
            let result = try block()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
    
    private func bind(_ stmt: OpaquePointer, arguments: [Any]) throws {
        for (index, val) in arguments.enumerated() {
            let idx = Int32(index + 1)
            let status: Int32
            if let str = val as? String {
                status = sqlite3_bind_text(stmt, idx, str, -1, transientDestructor)
            } else if let intVal = val as? Int {
                status = sqlite3_bind_int64(stmt, idx, Int64(intVal))
            } else if let doubleVal = val as? Double {
                status = sqlite3_bind_double(stmt, idx, doubleVal)
            } else if let boolVal = val as? Bool {
                status = sqlite3_bind_int64(stmt, idx, boolVal ? 1 : 0)
            } else if val is NSNull {
                status = sqlite3_bind_null(stmt, idx)
            } else {
                status = sqlite3_bind_null(stmt, idx)
            }
            if status != SQLITE_OK {
                throw DatabaseError.bindFailed(errorMessage())
            }
        }
    }
    
    private func errorMessage() -> String {
        return db != nil ? String(cString: sqlite3_errmsg(db)) : "Unknown database error"
    }
    
    public enum DatabaseError: Error, LocalizedError {
        case openFailed(String)
        case prepareFailed(String)
        case executionFailed(String)
        case bindFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .openFailed(let msg): return "Database open failed: \(msg)"
            case .prepareFailed(let msg): return "Database prepare query failed: \(msg)"
            case .executionFailed(let msg): return "Database execute failed: \(msg)"
            case .bindFailed(let msg): return "Database bind parameter failed: \(msg)"
            }
        }
    }
}