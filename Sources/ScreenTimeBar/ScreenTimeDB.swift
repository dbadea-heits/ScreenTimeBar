import Foundation
import SQLite3

/// Read-only access to the `screentime` daemon's SQLite database.
///
/// Every call opens, queries and closes its own handle: there is no shared
/// connection and no caching, so callers may invoke `read` from any thread
/// (the store dispatches it off the main actor).
enum ScreenTimeDB {
    enum DBError: LocalizedError {
        case notFound(String)
        case open(String)
        case query(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let path):
                return "Screen time database not found at \(path). "
                    + "Set a custom location with: defaults write com.local.ScreenTimeBar ScreenTimeDBPath \(path)"
            case .open(let message):
                return "Could not open the screen time database: \(message)"
            case .query(let message):
                return "Could not read the screen time database: \(message)"
            }
        }
    }

    /// `ScreenTimeDBPath` override → `$XDG_DATA_HOME/screentime/screentime.db`
    /// → `~/.local/share/screentime/screentime.db`.
    static func path() -> String {
        if let override = UserDefaults.standard.string(forKey: "ScreenTimeDBPath"), !override.isEmpty {
            return override
        }
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            return "\(xdg)/screentime/screentime.db"
        }
        return "\(NSHomeDirectory())/.local/share/screentime/screentime.db"
    }

    /// Inclusive `YYYY-MM-DD` range; returns `day -> (app -> seconds)`.
    /// Days without rows are simply absent from the result.
    static func read(from: String, to: String) throws -> [String: [String: Int]] {
        let p = path()
        guard FileManager.default.fileExists(atPath: p) else { throw DBError.notFound(p) }

        var db: OpaquePointer?
        if sqlite3_open_v2(p, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            // WAL contingency: retry once as an immutable read-only URI.
            sqlite3_close(db)
            db = nil
            let uri = "file:\(p)?mode=ro&immutable=1"
            guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
                let message = errorMessage(db)
                sqlite3_close(db)
                throw DBError.open(message)
            }
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT day, app, seconds FROM app_time WHERE day >= ? AND day <= ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.query(errorMessage(db))
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, from, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, to, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw DBError.query(errorMessage(db))
        }

        var result: [String: [String: Int]] = [:]
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                guard let dayText = sqlite3_column_text(stmt, 0),
                      let appText = sqlite3_column_text(stmt, 1) else { continue }
                let day = String(cString: dayText)
                let app = String(cString: appText)
                result[day, default: [:]][app] = Int(sqlite3_column_int64(stmt, 2))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw DBError.query(errorMessage(db))
            }
        }
        return result
    }

    private static func errorMessage(_ db: OpaquePointer?) -> String {
        guard let raw = sqlite3_errmsg(db) else { return "unknown SQLite error" }
        return String(cString: raw)
    }
}
