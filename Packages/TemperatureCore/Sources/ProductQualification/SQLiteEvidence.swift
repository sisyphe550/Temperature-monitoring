import CSQLite
import Foundation

struct SQLiteEvidence {
    let committedBatches: Int
    let cpuRawSamples: Int
    let gaps: Int

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
}
