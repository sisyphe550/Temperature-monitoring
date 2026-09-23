import CSQLite
import Foundation

struct LifecycleSQLiteEvidence {
    let sessionID: String
    let committedBatches: Int
    let gaps: Int
    let segments: Int
    let sources: Int
    let series: Int
}

struct EnduranceSQLiteEvidence {
    let committedBatches: Int
    let cpuRawSamples: Int
    let gaps: Int
    let rawSampleRows: Int
    let emaSampleRows: Int
    let aggregateRows: Int
    let aggregate1sRows: Int
    let aggregate10sRows: Int
    let aggregate1mRows: Int
}

struct SQLiteEvidence {
    let committedBatches: Int
    let cpuRawSamples: Int
    let gaps: Int

    static func lifecycle(databaseURL: URL) throws -> LifecycleSQLiteEvidence {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let connection else {
            throw QualificationError.invalidValue("sqlite")
        }
        defer {
            sqlite3_close(connection)
        }
        return LifecycleSQLiteEvidence(
            sessionID: try scalarText(connection, "SELECT session_id FROM session LIMIT 1"),
            committedBatches: try scalarInt(connection, "SELECT COUNT(*) FROM committed_batches"),
            gaps: try scalarInt(connection, "SELECT COUNT(*) FROM gaps"),
            segments: try scalarInt(connection, "SELECT COUNT(*) FROM segments"),
            sources: try scalarInt(connection, "SELECT COUNT(*) FROM sources"),
            series: try scalarInt(connection, "SELECT COUNT(*) FROM series")
        )
    }

    static func endurance(databaseURL: URL) throws -> EnduranceSQLiteEvidence {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let connection else {
            throw QualificationError.invalidValue("sqlite")
        }
        defer {
            sqlite3_close(connection)
        }
        return EnduranceSQLiteEvidence(
            committedBatches: try scalarInt(connection, "SELECT COUNT(*) FROM committed_batches"),
            cpuRawSamples: try scalarInt(connection, "SELECT COUNT(*) FROM raw_samples"),
            gaps: try scalarInt(connection, "SELECT COUNT(*) FROM gaps"),
            rawSampleRows: try scalarInt(connection, "SELECT COUNT(*) FROM raw_samples"),
            emaSampleRows: try scalarInt(connection, "SELECT COUNT(*) FROM ema_samples"),
            aggregateRows: try scalarInt(connection, "SELECT COUNT(*) FROM aggregates"),
            aggregate1sRows: try scalarInt(
                connection,
                "SELECT COUNT(*) FROM aggregates WHERE width_s = 1"
            ),
            aggregate10sRows: try scalarInt(
                connection,
                "SELECT COUNT(*) FROM aggregates WHERE width_s = 10"
            ),
            aggregate1mRows: try scalarInt(
                connection,
                "SELECT COUNT(*) FROM aggregates WHERE width_s = 60"
            )
        )
    }

    static func read(databaseURL: URL, periodMS: Int) throws -> SQLiteEvidence {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let connection else {
            throw QualificationError.invalidValue("sqlite")
        }
        defer {
            sqlite3_close(connection)
        }

        return SQLiteEvidence(
            committedBatches: try scalarInt(connection, "SELECT COUNT(*) FROM committed_batches"),
            cpuRawSamples: try scalarInt(
                connection,
                "SELECT COUNT(*) FROM raw_samples WHERE period_ms = ?",
                bind: [.int(periodMS)]
            ),
            gaps: try scalarInt(connection, "SELECT COUNT(*) FROM gaps")
        )
    }

    private enum BindValue {
        case int(Int)
    }

    private static func scalarInt(
        _ connection: OpaquePointer,
        _ sql: String,
        bind: [BindValue] = []
    ) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw QualificationError.invalidValue("sqlite_prepare")
        }
        defer {
            sqlite3_finalize(statement)
        }
        for (index, value) in bind.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .int(let number):
                sqlite3_bind_int(statement, position, Int32(number))
            }
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw QualificationError.invalidValue("sqlite_step")
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func scalarText(_ connection: OpaquePointer, _ sql: String) throws -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw QualificationError.invalidValue("sqlite_prepare")
        }
        defer {
            sqlite3_finalize(statement)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw QualificationError.invalidValue("sqlite_step")
        }
        guard let cString = sqlite3_column_text(statement, 0) else {
            throw QualificationError.invalidValue("sqlite_text")
        }
        return String(cString: cString)
    }
}
