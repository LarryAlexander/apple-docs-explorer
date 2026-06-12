import Foundation
import SQLite3

final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw DocsError.sqliteError(message)
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DocsError.sqliteError(String(cString: sqlite3_errmsg(handle)))
        }
        return statement
    }

    func errorMessage() -> String {
        String(cString: sqlite3_errmsg(handle))
    }
}

func bindText(_ value: String, index: Int32, to statement: OpaquePointer?) throws {
    let result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    guard result == SQLITE_OK else {
        throw DocsError.sqliteError("Could not bind text at index \(index).")
    }
}

func bindInt(_ value: Int, index: Int32, to statement: OpaquePointer?) throws {
    let result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
    guard result == SQLITE_OK else {
        throw DocsError.sqliteError("Could not bind integer at index \(index).")
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
