import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SQLiteAdapter: DatabaseAdapter {
    let databaseType: DatabaseType = .sqlite

    let capabilities = DatabaseCapabilities(
        transactions: .supported,
        queryCancelation: .unsupported,
        explainPlan: .partial,
        schemaIntrospection: .supported,
        ddlEditing: .supported,
        parameterizedQueries: .supported,
        streamingResults: .unsupported
    )

    func testConnection(_ configuration: DatabaseConnectionConfiguration) async throws {
        _ = try resolvedPath(from: configuration)
    }

    func openSession(_ configuration: DatabaseConnectionConfiguration) async throws -> any DatabaseSession {
        let path = try resolvedPath(from: configuration)
        return try SQLiteSession(path: path, capabilities: capabilities)
    }

    private func resolvedPath(from configuration: DatabaseConnectionConfiguration) throws -> String {
        guard configuration.databaseType == .sqlite else {
            throw DatabaseAdapterError.configurationInvalid(reason: "Expected SQLite configuration")
        }

        switch configuration.transport {
        case .connectionString(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw DatabaseAdapterError.configurationInvalid(reason: "SQLite path is empty")
            }
            return trimmed
        case .hostPort, .sshTunnel:
            let db = configuration.databaseName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard db.isEmpty == false else {
                throw DatabaseAdapterError.configurationInvalid(reason: "SQLite database path is required")
            }
            return db
        case .unixSocket(let path):
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw DatabaseAdapterError.configurationInvalid(reason: "SQLite path is empty")
            }
            return trimmed
        }
    }
}

private final class SQLiteSession: DatabaseSession {
    let id = UUID()
    let databaseType: DatabaseType = .sqlite
    let capabilities: DatabaseCapabilities

    private var db: OpaquePointer?

    init(path: String, capabilities: DatabaseCapabilities) throws {
        self.capabilities = capabilities
        let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            db = nil
            throw DatabaseAdapterError.queryFailed(message: message, sqlState: nil)
        }
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    func disconnect() async {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    func ping() async throws {
        _ = try await execute(QueryExecutionRequest(sql: "SELECT 1 AS ping"))
    }

    func execute(_ request: QueryExecutionRequest) async throws -> QueryExecutionResult {
        guard let db else {
            throw DatabaseAdapterError.configurationInvalid(reason: "SQLite session is closed")
        }

        let startedAt = Date()
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let prepared = sqlite3_prepare_v2(db, request.sql, -1, &statement, nil)
        guard prepared == SQLITE_OK else {
            throw DatabaseAdapterError.queryFailed(
                message: String(cString: sqlite3_errmsg(db)),
                sqlState: nil
            )
        }

        try bind(parameters: request.parameters, to: statement)

        var columns: [QueryColumn] = []
        var rows: [[DatabaseValue]] = []
        var affectedRows: Int?

        var didReadHeader = false
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                if didReadHeader == false {
                    columns = readColumns(from: statement)
                    didReadHeader = true
                }
                rows.append(readRow(from: statement, columnCount: columns.count))
                if let limit = request.limitRows, rows.count >= limit {
                    break
                }
            } else if step == SQLITE_DONE {
                if didReadHeader == false {
                    affectedRows = Int(sqlite3_changes(db))
                }
                break
            } else {
                throw DatabaseAdapterError.queryFailed(
                    message: String(cString: sqlite3_errmsg(db)),
                    sqlState: nil
                )
            }
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        return QueryExecutionResult(
            queryID: request.id,
            columns: columns,
            rows: rows,
            affectedRows: affectedRows,
            durationMs: durationMs
        )
    }

    func stream(_ request: QueryExecutionRequest) -> AsyncThrowingStream<QueryExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await execute(request)
                    if result.columns.isEmpty == false {
                        continuation.yield(.header(result.columns))
                    }
                    if result.rows.isEmpty == false {
                        continuation.yield(.rows(result.rows))
                    }
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func cancel(queryID: UUID) async {
        // SQLite cancellation support can be added with sqlite3_interrupt when long queries are tracked.
    }

    func introspect(_ request: SchemaIntrospectionRequest) async throws -> SchemaSnapshot {
        let sql = """
        SELECT name, type
        FROM sqlite_master
        WHERE type IN ('table', 'view')
        ORDER BY type, name;
        """

        let result = try await execute(QueryExecutionRequest(sql: sql))
        let objects: [SchemaObject] = result.rows.compactMap { row in
            guard row.count >= 2 else { return nil }
            guard case .string(let name) = row[0], case .string(let type) = row[1] else { return nil }

            if request.includeViews == false, type == "view" {
                return nil
            }

            let kind: SchemaObjectKind = (type == "view") ? .view : .table
            return SchemaObject(path: name, kind: kind, columns: [])
        }

        return SchemaSnapshot(objects: objects)
    }

    func quoteIdentifier(_ identifier: String) -> String {
        let escaped = identifier.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func bind(parameters: [QueryParameter], to statement: OpaquePointer?) throws {
        guard parameters.isEmpty == false else { return }

        for (index, parameter) in parameters.enumerated() {
            let position = Int32(index + 1)
            switch parameter.value {
            case .null:
                sqlite3_bind_null(statement, position)
            case .integer(let value):
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case .double(let value):
                sqlite3_bind_double(statement, position, value)
            case .string(let value):
                _ = value.withCString { raw in
                    sqlite3_bind_text(statement, position, raw, -1, SQLITE_TRANSIENT)
                }
            case .bool(let value):
                sqlite3_bind_int(statement, position, value ? 1 : 0)
            case .date(let value):
                sqlite3_bind_double(statement, position, value.timeIntervalSince1970)
            case .binary(let data):
                data.withUnsafeBytes { rawBuffer in
                    if let baseAddress = rawBuffer.baseAddress {
                        sqlite3_bind_blob(statement, position, baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                    }
                }
            }
        }
    }

    private func readColumns(from statement: OpaquePointer?) -> [QueryColumn] {
        let count = sqlite3_column_count(statement)
        guard count > 0 else { return [] }

        return (0..<count).map { index in
            let name = String(cString: sqlite3_column_name(statement, index))
            let type = sqlite3_column_decltype(statement, index).map { String(cString: $0) } ?? "UNKNOWN"
            return QueryColumn(name: name, databaseTypeName: type, isNullable: true)
        }
    }

    private func readRow(from statement: OpaquePointer?, columnCount: Int) -> [DatabaseValue] {
        guard columnCount > 0 else { return [] }

        return (0..<columnCount).map { index in
            let type = sqlite3_column_type(statement, Int32(index))
            switch type {
            case SQLITE_INTEGER:
                return .integer(sqlite3_column_int64(statement, Int32(index)))
            case SQLITE_FLOAT:
                return .double(sqlite3_column_double(statement, Int32(index)))
            case SQLITE_TEXT:
                if let value = sqlite3_column_text(statement, Int32(index)) {
                    return .string(String(cString: value))
                }
                return .null
            case SQLITE_BLOB:
                guard let raw = sqlite3_column_blob(statement, Int32(index)) else {
                    return .null
                }
                let length = Int(sqlite3_column_bytes(statement, Int32(index)))
                return .binary(Data(bytes: raw, count: length))
            default:
                return .null
            }
        }
    }
}
