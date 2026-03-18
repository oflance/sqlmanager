import Foundation
import Logging
import NIOCore
import PostgresNIO

struct PostgreSQLAdapter: DatabaseAdapter {
    let databaseType: DatabaseType = .postgresql

    let capabilities = DatabaseCapabilities(
        transactions: .supported,
        queryCancelation: .supported,
        explainPlan: .supported,
        schemaIntrospection: .supported,
        ddlEditing: .supported,
        parameterizedQueries: .supported,
        streamingResults: .supported
    )

    func testConnection(_ configuration: DatabaseConnectionConfiguration) async throws {
        _ = try makeClientConfiguration(from: configuration)
        let session = try PostgreSQLSession(configuration: configuration, capabilities: capabilities)
        defer {
            Task {
                await session.disconnect()
            }
        }
        try await session.ping()
    }

    func openSession(_ configuration: DatabaseConnectionConfiguration) async throws -> any DatabaseSession {
        let session = try PostgreSQLSession(configuration: configuration, capabilities: capabilities)
        try await session.ping()
        return session
    }

    fileprivate func makeClientConfiguration(from configuration: DatabaseConnectionConfiguration) throws
        -> PostgresClient.Configuration
    {
        let username = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard username.isEmpty == false else {
            throw DatabaseAdapterError.configurationInvalid(reason: "Username is required")
        }

        let password: String?
        switch configuration.credential {
        case .password(let value), .token(let value):
            password = value
        case .none:
            password = nil
        }

        let tls: PostgresClient.Configuration.TLS = configuration.useSSL
            ? .prefer(.makeClientConfiguration())
            : .disable

        switch configuration.transport {
        case .hostPort(let host, let port):
            let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedHost.isEmpty == false else {
                throw DatabaseAdapterError.configurationInvalid(reason: "Host is required")
            }
            guard port > 0 else {
                throw DatabaseAdapterError.configurationInvalid(reason: "Port must be greater than 0")
            }
            let database = databaseName(from: configuration)
            return PostgresClient.Configuration(
                host: normalizedHost,
                port: port,
                username: username,
                password: password,
                database: database,
                tls: tls
            )

        case .connectionString(let value):
            guard let components = URLComponents(string: value) else {
                throw DatabaseAdapterError.configurationInvalid(reason: "Invalid connection string")
            }
            guard let host = components.host, host.isEmpty == false else {
                throw DatabaseAdapterError.configurationInvalid(reason: "Connection string host is missing")
            }
            let port = components.port ?? 5432
            let dbPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let database = dbPath.isEmpty ? databaseName(from: configuration) : dbPath
            let user = (components.user?.isEmpty == false) ? components.user! : username
            let pass = components.password ?? password
            return PostgresClient.Configuration(
                host: host,
                port: port,
                username: user,
                password: pass,
                database: database,
                tls: tls
            )

        case .unixSocket(let path):
            let socketPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard socketPath.isEmpty == false else {
                throw DatabaseAdapterError.configurationInvalid(reason: "Socket path is empty")
            }
            return PostgresClient.Configuration(
                unixSocketPath: socketPath,
                username: username,
                password: password,
                database: databaseName(from: configuration)
            )

        case .sshTunnel(let tunnel):
            let host = tunnel.targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard host.isEmpty == false else {
                throw DatabaseAdapterError.configurationInvalid(reason: "SSH tunnel target host is empty")
            }
            guard tunnel.targetPort > 0 else {
                throw DatabaseAdapterError.configurationInvalid(reason: "SSH tunnel target port must be greater than 0")
            }
            return PostgresClient.Configuration(
                host: host,
                port: tunnel.targetPort,
                username: username,
                password: password,
                database: databaseName(from: configuration),
                tls: tls
            )
        }
    }

    private func databaseName(from configuration: DatabaseConnectionConfiguration) -> String {
        let trimmed = configuration.databaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? configuration.username : trimmed
    }
}

private final class PostgreSQLSession: DatabaseSession {
    let id = UUID()
    let databaseType: DatabaseType = .postgresql
    let capabilities: DatabaseCapabilities

    private let client: PostgresClient
    private let runTask: Task<Void, Never>
    private let logger = Logger(label: "com.oflance.sqlmanager.postgresql")
    private var isClosed = false

    init(configuration: DatabaseConnectionConfiguration, capabilities: DatabaseCapabilities) throws {
        self.capabilities = capabilities
        let clientConfiguration = try PostgreSQLAdapter().makeClientConfiguration(from: configuration)
        let client = PostgresClient(configuration: clientConfiguration)
        self.client = client
        self.runTask = Task {
            await client.run()
        }
    }

    func disconnect() async {
        isClosed = true
        runTask.cancel()
        _ = await runTask.result
    }

    func ping() async throws {
        _ = try await execute(QueryExecutionRequest(sql: "SELECT 1 AS ping"))
    }

    func execute(_ request: QueryExecutionRequest) async throws -> QueryExecutionResult {
        guard isClosed == false else {
            throw DatabaseAdapterError.configurationInvalid(reason: "PostgreSQL session is closed")
        }

        let query = PostgresQuery(unsafeSQL: request.sql)
        let startedAt = Date()

        do {
            let response: PostgresQueryResult = try await client.withConnection { connection in
                try await connection.query(query, logger: logger).get()
            }

            let rows: [[DatabaseValue]] = response.rows.map { row in
                row.map(parseCell)
            }

            let columns: [QueryColumn]
            if let firstRow = response.rows.first {
                columns = firstRow.map { cell in
                    QueryColumn(
                        name: cell.columnName,
                        databaseTypeName: String(describing: cell.dataType),
                        isNullable: true
                    )
                }
            } else {
                columns = []
            }

            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            return QueryExecutionResult(
                queryID: request.id,
                columns: columns,
                rows: rows,
                affectedRows: response.metadata.rows,
                durationMs: durationMs
            )
        } catch {
            throw mapPostgresError(error)
        }
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
        // Native cancel support can be added by tracking query tasks and cancelling the specific in-flight command.
    }

    func introspect(_ request: SchemaIntrospectionRequest) async throws -> SchemaSnapshot {
        func stringValue(_ value: DatabaseValue) -> String? {
            if case .string(let string) = value { return string }
            return nil
        }

        func boolValue(_ value: DatabaseValue) -> Bool? {
            switch value {
            case .bool(let bool):
                return bool
            case .string(let string):
                switch string.uppercased() {
                case "YES", "TRUE", "1":
                    return true
                case "NO", "FALSE", "0":
                    return false
                default:
                    return nil
                }
            default:
                return nil
            }
        }

        func parseIndexColumns(from definition: String) -> [String] {
            guard let open = definition.firstIndex(of: "("), let close = definition.lastIndex(of: ")"), open < close else {
                return []
            }
            let raw = definition[definition.index(after: open)..<close]
            return raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { value -> String in
                    if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                        return String(value.dropFirst().dropLast())
                    }
                    return value
                }
        }

        var clauses: [String] = []
        if request.includeSystemObjects == false {
            clauses.append("table_schema NOT IN ('pg_catalog', 'information_schema')")
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE \(clauses.joined(separator: " AND "))"
        let sql = """
        SELECT table_schema || '.' || table_name AS object_name, table_type
        FROM information_schema.tables
        \(whereClause)
        ORDER BY table_schema, table_name
        """

        let tableResult = try await execute(QueryExecutionRequest(sql: sql))
        var objects: [SchemaObject] = tableResult.rows.compactMap { row in
            guard row.count >= 2 else { return nil }
            guard let path = stringValue(row[0]), let type = stringValue(row[1]) else { return nil }

            if request.includeViews == false, type.uppercased().contains("VIEW") {
                return nil
            }

            let kind: SchemaObjectKind = type.uppercased().contains("VIEW") ? .view : .table
            return SchemaObject(path: path, kind: kind, columns: [])
        }

        let columnsSQL = """
        SELECT table_schema || '.' || table_name AS object_name, column_name, data_type, is_nullable = 'YES' AS is_nullable
        FROM information_schema.columns
        \(whereClause)
        ORDER BY table_schema, table_name, ordinal_position
        """
        let columnResult = try await execute(QueryExecutionRequest(sql: columnsSQL))

        var columnsByObjectPath: [String: [SchemaColumn]] = [:]
        for row in columnResult.rows {
            guard row.count >= 4 else { continue }
            guard let objectPath = stringValue(row[0]), let columnName = stringValue(row[1]), let typeName = stringValue(row[2]) else {
                continue
            }
            let isNullable = boolValue(row[3]) ?? true
            columnsByObjectPath[objectPath, default: []].append(
                SchemaColumn(name: columnName, typeName: typeName, isNullable: isNullable)
            )
        }

        objects = objects.map { object in
            var mutable = object
            mutable.columns = columnsByObjectPath[object.path] ?? []
            return mutable
        }

        if request.includeIndexes {
            var indexClauses: [String] = []
            if request.includeSystemObjects == false {
                indexClauses.append("schemaname NOT IN ('pg_catalog', 'information_schema')")
            }
            let indexWhereClause = indexClauses.isEmpty ? "" : "WHERE \(indexClauses.joined(separator: " AND "))"
            let indexesSQL = """
            SELECT schemaname || '.' || tablename AS table_path, indexname, indexdef
            FROM pg_indexes
            \(indexWhereClause)
            ORDER BY schemaname, tablename, indexname
            """

            let indexResult = try await execute(QueryExecutionRequest(sql: indexesSQL))
            let indexObjects: [SchemaObject] = indexResult.rows.compactMap { row in
                guard row.count >= 3 else { return nil }
                guard let tablePath = stringValue(row[0]), let indexName = stringValue(row[1]), let indexDefinition = stringValue(row[2]) else {
                    return nil
                }

                let indexColumns = parseIndexColumns(from: indexDefinition).map { column in
                    SchemaColumn(name: column, typeName: "INDEX_COLUMN", isNullable: true)
                }
                return SchemaObject(path: "\(tablePath).\(indexName)", kind: .index, columns: indexColumns)
            }

            objects.append(contentsOf: indexObjects)
        }

        var constraintClauses: [String] = []
        if request.includeSystemObjects == false {
            constraintClauses.append("tc.table_schema NOT IN ('pg_catalog', 'information_schema')")
        }
        let constraintWhereClause = constraintClauses.isEmpty ? "" : "WHERE \(constraintClauses.joined(separator: " AND "))"
        let constraintsSQL = """
        SELECT
            tc.table_schema || '.' || tc.table_name AS table_path,
            tc.constraint_name,
            tc.constraint_type,
            kcu.column_name
        FROM information_schema.table_constraints tc
        LEFT JOIN information_schema.key_column_usage kcu
            ON tc.constraint_schema = kcu.constraint_schema
            AND tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
            AND tc.table_name = kcu.table_name
        \(constraintWhereClause)
        ORDER BY tc.table_schema, tc.table_name, tc.constraint_name, kcu.ordinal_position
        """

        let constraintResult = try await execute(QueryExecutionRequest(sql: constraintsSQL))
        var constraintColumnsByPath: [String: [SchemaColumn]] = [:]
        for row in constraintResult.rows {
            guard row.count >= 4 else { continue }
            guard let tablePath = stringValue(row[0]), let constraintName = stringValue(row[1]), let constraintType = stringValue(row[2]) else {
                continue
            }

            let constraintPath = "\(tablePath).\(constraintName)"
            if constraintColumnsByPath[constraintPath] == nil {
                constraintColumnsByPath[constraintPath] = []
            }

            if let columnName = stringValue(row[3]), columnName.isEmpty == false {
                constraintColumnsByPath[constraintPath, default: []].append(
                    SchemaColumn(name: columnName, typeName: constraintType, isNullable: true)
                )
            }
        }

        let constraintObjects = constraintColumnsByPath
            .map { path, columns in
                SchemaObject(path: path, kind: .constraint, columns: columns)
            }
            .sorted { $0.path < $1.path }
        objects.append(contentsOf: constraintObjects)

        return SchemaSnapshot(objects: objects)
    }

    func quoteIdentifier(_ identifier: String) -> String {
        let escaped = identifier.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func parseCell(_ cell: PostgresCell) -> DatabaseValue {
        if cell.bytes == nil {
            return .null
        }

        if let boolValue = try? cell.decode(Bool.self) {
            return .bool(boolValue)
        }
        if let intValue = try? cell.decode(Int64.self) {
            return .integer(intValue)
        }
        if let doubleValue = try? cell.decode(Double.self) {
            return .double(doubleValue)
        }
        if let dateValue = try? cell.decode(Date.self) {
            return .date(dateValue)
        }
        if let stringValue = try? cell.decode(String.self) {
            return .string(stringValue)
        }
        if let byteBuffer = try? cell.decode(ByteBuffer.self) {
            return .binary(Data(byteBuffer.readableBytesView))
        }

        return .string("<unsupported>")
    }

    private func mapPostgresError(_ error: Error) -> DatabaseAdapterError {
        if let ioError = error as? IOError {
            let reason: String
            switch ioError.errnoCode {
            case 1:
                reason = "Operation not permitted by OS policy (errno: 1). Check App Sandbox network client entitlement."
            case 61:
                reason = "Connection refused (errno: 61). Check host/port and that DB server is listening and reachable."
            case 60:
                reason = "Connection timed out (errno: 60). Host reachable check failed or port blocked by firewall/network."
            case 54:
                reason = "Connection reset by peer (errno: 54). Server closed the socket during handshake/query."
            default:
                reason = "\(ioError.reason) (errno: \(ioError.errnoCode))"
            }
            return .networkUnavailable(reason: reason)
        }

        if let postgresError = error as? PSQLError {
            if postgresError.code == .queryCancelled {
                return .cancelled
            }
            if postgresError.code == .connectionError
                || postgresError.code == .serverClosedConnection
                || postgresError.code == .clientClosedConnection
            {
                return .networkUnavailable(reason: postgresError.localizedDescription)
            }

            let message = postgresError.serverInfo?[.message] ?? postgresError.localizedDescription
            let sqlState = postgresError.serverInfo?[.sqlState]

            if message.localizedCaseInsensitiveContains("password")
                || message.localizedCaseInsensitiveContains("authentication")
            {
                return .authenticationFailed(reason: message)
            }

            return .queryFailed(message: message, sqlState: sqlState)
        }

        if let localized = (error as? LocalizedError)?.errorDescription {
            return .queryFailed(message: localized, sqlState: nil)
        }
        return .queryFailed(message: error.localizedDescription, sqlState: nil)
    }
}
