import CSQLite
import Foundation

enum SQLiteStoreError: Error, Sendable, Equatable {
    case openFailed(code: Int32, message: String)
    case execFailed(code: Int32, message: String)
    case prepareFailed(code: Int32, message: String)
    case stepFailed(code: Int32, message: String)
    case quickCheckFailed(result: String)
    case schemaMismatch(detail: String)
    case integrityConflict(detail: String)
    case closed
}

final class SQLiteStore: @unchecked Sendable {
    static let expectedUserVersion = 1
    static let requiredViews = ["samples_1s", "samples_10s", "samples_1m"]

    private var handle: OpaquePointer?
    let databaseURL: URL

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try open()
    }

    deinit {
        close()
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    func userVersion() throws -> Int {
        guard let value = try queryInt64("PRAGMA user_version") else {
            throw SQLiteStoreError.schemaMismatch(detail: "missing user_version")
        }
        return Int(value)
    }

    func quickCheck() throws {
        guard let result = try queryString("PRAGMA quick_check") else {
            throw SQLiteStoreError.quickCheckFailed(result: "empty")
        }
        guard result.lowercased() == "ok" else {
            throw SQLiteStoreError.quickCheckFailed(result: result)
        }
    }

    func foreignKeysEnabled() throws -> Bool {
        guard let value = try queryInt64("PRAGMA foreign_keys") else {
            return false
        }
        return value == 1
    }

    func applyBundledSchemaIfNeeded() throws {
        if try userVersion() == Self.expectedUserVersion {
            try validateSchema()
            return
        }
        if try tableExists("session") == false {
            let sql = try Self.loadBundledSchemaSQL()
            try exec(sql)
        }
        guard try userVersion() == Self.expectedUserVersion else {
            throw SQLiteStoreError.schemaMismatch(
                detail: "expected user_version \(Self.expectedUserVersion), got \(try userVersion())"
            )
        }
        try validateSchema()
    }

    func insertSession(_ metadata: SessionMetadata) throws {
        let sql = """
        INSERT INTO session (session_id, started_wall_ns, model, os_build, app_version)
        VALUES (?, ?, ?, ?, ?)
        """
        try bindAndRun(
            sql: sql,
            bindings: [
                .text(metadata.sessionID.rawValue),
                .int64(metadata.startedWallUnixNS),
                .text(metadata.model),
                .text(metadata.osBuild),
                .text(metadata.appVersion),
            ]
        )
    }

    func sessionRow(for sessionID: SessionID) throws -> SessionMetadata? {
        let sql = """
        SELECT started_wall_ns, model, os_build, app_version
        FROM session
        WHERE session_id = ?
        LIMIT 1
        """
        return try queryRow(sql: sql, bindings: [.text(sessionID.rawValue)]) { statement in
            let started = sqlite3_column_int64(statement, 0)
            guard let model = sqlite3_column_text(statement, 1),
                  let osBuild = sqlite3_column_text(statement, 2),
                  let appVersion = sqlite3_column_text(statement, 3)
            else {
                throw SQLiteStoreError.schemaMismatch(detail: "invalid session row")
            }
            return SessionMetadata(
                sessionID: sessionID,
                startedWallUnixNS: started,
                model: String(cString: model),
                osBuild: String(cString: osBuild),
                appVersion: String(cString: appVersion)
            )
        }
    }

    func validateSchemaForExistingDatabase() throws {
        try quickCheck()
        try validateSchema()
    }

    func execSQL(_ sql: String) throws {
        try exec(sql)
    }

    func viewExists(_ name: String) throws -> Bool {
        let sql = """
        SELECT 1 FROM sqlite_master WHERE type = 'view' AND name = ? LIMIT 1
        """
        return try queryExists(sql: sql, bindings: [.text(name)])
    }

    private func open() throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let code = databaseURL.path.withCString { path in
            sqlite3_open_v2(path, &db, flags, nil)
        }
        guard code == SQLITE_OK, let db else {
            throw SQLiteStoreError.openFailed(code: code, message: Self.lastErrorMessage(from: db))
        }
        handle = db
    }

    private func validateSchema() throws {
        guard try foreignKeysEnabled() else {
            throw SQLiteStoreError.schemaMismatch(detail: "foreign_keys disabled")
        }
        for view in Self.requiredViews {
            guard try viewExists(view) else {
                throw SQLiteStoreError.schemaMismatch(detail: "missing view \(view)")
            }
        }
        guard try tableExists("session") else {
            throw SQLiteStoreError.schemaMismatch(detail: "missing session table")
        }
    }

    private func tableExists(_ name: String) throws -> Bool {
        let sql = """
        SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1
        """
        return try queryExists(sql: sql, bindings: [.text(name)])
    }

    func exec(_ sql: String) throws {
        guard let handle else { throw SQLiteStoreError.closed }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        defer {
            if let errorMessage {
                sqlite3_free(errorMessage)
            }
        }
        guard code == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? Self.lastErrorMessage(from: handle)
            throw SQLiteStoreError.execFailed(code: code, message: message)
        }
    }

    enum Binding {
        case text(String)
        case optionalText(String?)
        case int64(Int64)
        case optionalInt64(Int64?)
        case double(Double)
        case optionalDouble(Double?)
    }

    func bindAndRun(sql: String, bindings: [Binding]) throws {
        guard let handle else { throw SQLiteStoreError.closed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.prepareFailed(
                code: sqlite3_errcode(handle),
                message: Self.lastErrorMessage(from: handle)
            )
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            let code: Int32
            switch binding {
            case .text(let value):
                code = value.withCString { sqlite3_bind_text(statement, position, $0, -1, SQLITE_TRANSIENT) }
            case .optionalText(let value):
                if let value {
                    code = value.withCString { sqlite3_bind_text(statement, position, $0, -1, SQLITE_TRANSIENT) }
                } else {
                    code = sqlite3_bind_null(statement, position)
                }
            case .int64(let value):
                code = sqlite3_bind_int64(statement, position, value)
            case .optionalInt64(let value):
                if let value {
                    code = sqlite3_bind_int64(statement, position, value)
                } else {
                    code = sqlite3_bind_null(statement, position)
                }
            case .double(let value):
                code = sqlite3_bind_double(statement, position, value)
            case .optionalDouble(let value):
                if let value {
                    code = sqlite3_bind_double(statement, position, value)
                } else {
                    code = sqlite3_bind_null(statement, position)
                }
            }
            guard code == SQLITE_OK else {
                throw SQLiteStoreError.prepareFailed(code: code, message: Self.lastErrorMessage(from: handle))
            }
        }

        let stepCode = sqlite3_step(statement)
        guard stepCode == SQLITE_DONE else {
            throw SQLiteStoreError.stepFailed(code: stepCode, message: Self.lastErrorMessage(from: handle))
        }
    }

    func queryExists(sql: String, bindings: [Binding]) throws -> Bool {
        try queryRow(sql: sql, bindings: bindings) { _ in true } != nil
    }

    func queryInt64(_ sql: String) throws -> Int64? {
        try queryRow(sql: sql, bindings: []) { statement in
            sqlite3_column_int64(statement, 0)
        }
    }

    private func queryString(_ sql: String) throws -> String? {
        guard let handle else { throw SQLiteStoreError.closed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.prepareFailed(
                code: sqlite3_errcode(handle),
                message: Self.lastErrorMessage(from: handle)
            )
        }
        defer { sqlite3_finalize(statement) }

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let text = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: text)
        case SQLITE_DONE:
            return nil
        default:
            throw SQLiteStoreError.stepFailed(
                code: sqlite3_errcode(handle),
                message: Self.lastErrorMessage(from: handle)
            )
        }
    }

    func queryRow<T>(
        sql: String,
        bindings: [Binding],
        map: (OpaquePointer) throws -> T
    ) throws -> T? {
        guard let handle else { throw SQLiteStoreError.closed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteStoreError.prepareFailed(
                code: sqlite3_errcode(handle),
                message: Self.lastErrorMessage(from: handle)
            )
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch binding {
            case .text(let value):
                _ = value.withCString { sqlite3_bind_text(statement, position, $0, -1, SQLITE_TRANSIENT) }
            case .optionalText(let value):
                if let value {
                    _ = value.withCString { sqlite3_bind_text(statement, position, $0, -1, SQLITE_TRANSIENT) }
                } else {
                    _ = sqlite3_bind_null(statement, position)
                }
            case .int64(let value):
                _ = sqlite3_bind_int64(statement, position, value)
            case .optionalInt64(let value):
                if let value {
                    _ = sqlite3_bind_int64(statement, position, value)
                } else {
                    _ = sqlite3_bind_null(statement, position)
                }
            case .double(let value):
                _ = sqlite3_bind_double(statement, position, value)
            case .optionalDouble(let value):
                if let value {
                    _ = sqlite3_bind_double(statement, position, value)
                } else {
                    _ = sqlite3_bind_null(statement, position)
                }
            }
        }

        let stepCode = sqlite3_step(statement)
        guard stepCode == SQLITE_ROW else {
            if stepCode == SQLITE_DONE {
                return nil
            }
            throw SQLiteStoreError.stepFailed(code: stepCode, message: Self.lastErrorMessage(from: handle))
        }
        return try map(statement)
    }

    private static func loadBundledSchemaSQL() throws -> String {
        guard let url = Bundle.module.url(forResource: "schema-v1", withExtension: "sql") else {
            throw SQLiteStoreError.schemaMismatch(detail: "missing bundled schema resource")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func lastErrorMessage(from handle: OpaquePointer?) -> String {
        guard let handle, let message = sqlite3_errmsg(handle) else {
            return "unknown sqlite error"
        }
        return String(cString: message)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
