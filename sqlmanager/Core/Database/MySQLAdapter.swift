import Foundation
import Logging
import MySQLNIO
import NIOCore
import NIOPosix
import NIOSSL

struct MySQLAdapter: DatabaseAdapter {
    let databaseType: DatabaseType = .mysql

    let capabilities = DatabaseCapabilities(
        transactions: .supported,
        queryCancelation: .partial,
        explainPlan: .supported,
        schemaIntrospection: .supported,
        ddlEditing: .supported,
        parameterizedQueries: .supported,
        streamingResults: .supported
    )

    func testConnection(_ configuration: DatabaseConnectionConfiguration) async throws {
        let session = try await MySQLSession.connect(configuration: configuration, capabilities: capabilities)
        defer {
            Task {
                await session.disconnect()
            }
        }
        try await session.ping()
    }

    func openSession(_ configuration: DatabaseConnectionConfiguration) async throws -> any DatabaseSession {
        let session = try await MySQLSession.connect(configuration: configuration, capabilities: capabilities)
        try await session.ping()
        return session
    }

    fileprivate func makeConnectionTarget(from configuration: DatabaseConnectionConfiguration) throws -> MySQLConnectionTarget {
        guard configuration.databaseType == .mysql else {
            throw DatabaseAdapterError.configurationInvalid(reason: "Expected MySQL configuration")
        }

        let fallbackUsername = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDatabase = normalizedDatabase(from: configuration)
        let fallbackPassword = credentialString(from: configuration)

        switch configuration.transport {
        case .hostPort(let host, let port):
            let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedHost.isEmpty == false else {
                throw DatabaseAdapterError.configurationInvalid(reason: "Host is required")
            }
            guard port > 0 else {
                throw DatabaseAdapterError.configurationInvalid(reason: "Port must be greater than 0")
            }

            return MySQLConnectionTarget(
                socketAddress: try .makeAddressResolvingHost(normalizedHost, port: port),
                username: fallbackUsername,
                password: fallbackPassword,
                database: fallbackDatabase,
                tlsConfiguration: configuration.useSSL ? .makeClientConfiguration() : nil,
                serverHostname: configuration.useSSL ? normalizedHost : nil
            )

        case .connectionString(let value):
            guard let components = URLComponents(string: value) else {
                throw DatabaseAdapterError.configurationInvalid(reason: "Invalid connection string")
            }

            let scheme = components.scheme?.lowercased()
            let resolvedSSL = (scheme == "mysqls") || configuration.useSSL

            let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = components.port ?? 3306
            let username = (components.user?.isEmpty == false) ? components.user! : fallbackUsername
            let password = components.password ?? fallbackPassword

            let dbPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let database = dbPath.isEmpty ? fallbackDatabase : dbPath

            if let host, host.isEmpty == false {
                return MySQLConnectionTarget(
                    socketAddress: try .makeAddressResolvingHost(host, port: port),
                    username: username,
                    password: password,
                    database: database,
                    tlsConfiguration: resolvedSSL ? .makeClientConfiguration() : nil,
                    serverHostname: resolvedSSL ? host : nil
                )
            }

            throw DatabaseAdapterError.configurationInvalid(reason: "Connection string host is missing")

        case .unixSocket(let path):
            let socketPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard socketPath.isEmpty == false else {
                throw DatabaseAdapterError.configurationInvalid(reason: "Socket path is empty")
            }

            return MySQLConnectionTarget(
                socketAddress: try .init(unixDomainSocketPath: socketPath),
                username: fallbackUsername,
                password: fallbackPassword,
                database: fallbackDatabase,
                tlsConfiguration: nil,
                serverHostname: nil
            )

        case .sshTunnel(let tunnel):
            let host = tunnel.targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard host.isEmpty == false else {
                throw DatabaseAdapterError.configurationInvalid(reason: "SSH tunnel target host is empty")
            }
            guard tunnel.targetPort > 0 else {
                throw DatabaseAdapterError.configurationInvalid(reason: "SSH tunnel target port must be greater than 0")
            }

            return MySQLConnectionTarget(
                socketAddress: try .makeAddressResolvingHost(host, port: tunnel.targetPort),
                username: fallbackUsername,
                password: fallbackPassword,
                database: fallbackDatabase,
                tlsConfiguration: configuration.useSSL ? .makeClientConfiguration() : nil,
                serverHostname: configuration.useSSL ? host : nil
            )
        }
    }

    private func normalizedDatabase(from configuration: DatabaseConnectionConfiguration) -> String {
        let database = configuration.databaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if database.isEmpty == false {
            return database
        }
        let fallback = configuration.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback
    }

    private func credentialString(from configuration: DatabaseConnectionConfiguration) -> String? {
        switch configuration.credential {
        case .password(let value), .token(let value):
            return value
        case .none:
            return nil
        }
    }
}

private struct MySQLConnectionTarget {
    let socketAddress: SocketAddress
    let username: String
    let password: String?
    let database: String
    let tlsConfiguration: TLSConfiguration?
    let serverHostname: String?
}

private final class MySQLSession: DatabaseSession {
    let id = UUID()
    let databaseType: DatabaseType = .mysql
    let capabilities: DatabaseCapabilities

    private let connection: MySQLConnection
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let logger = Logger(label: "com.oflance.sqlmanager.mysql")
    private var isClosed = false

    private init(connection: MySQLConnection, eventLoopGroup: MultiThreadedEventLoopGroup, capabilities: DatabaseCapabilities) {
        self.connection = connection
        self.eventLoopGroup = eventLoopGroup
        self.capabilities = capabilities
    }

    static func connect(configuration: DatabaseConnectionConfiguration, capabilities: DatabaseCapabilities) async throws -> MySQLSession {
        let target = try MySQLAdapter().makeConnectionTarget(from: configuration)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        do {
            let connection = try await MySQLConnection.connect(
                to: target.socketAddress,
                username: target.username,
                database: target.database,
                password: target.password,
                tlsConfiguration: target.tlsConfiguration,
                serverHostname: target.serverHostname,
                logger: Logger(label: "com.oflance.sqlmanager.mysql"),
                on: group.next()
            ).get()
            return MySQLSession(connection: connection, eventLoopGroup: group, capabilities: capabilities)
        } catch {
            await shutdown(group)
            throw mapMySQLError(error)
        }
    }

    func disconnect() async {
        guard isClosed == false else { return }
        isClosed = true

        _ = try? await connection.close().get()
        await Self.shutdown(eventLoopGroup)
    }

    func ping() async throws {
        _ = try await execute(QueryExecutionRequest(sql: "SELECT 1 AS ping"))
    }

    func execute(_ request: QueryExecutionRequest) async throws -> QueryExecutionResult {
        guard isClosed == false else {
            throw DatabaseAdapterError.configurationInvalid(reason: "MySQL session is closed")
        }

        let binds = request.parameters.map(convertParameter)
        let startedAt = Date()
        var metadata: MySQLQueryMetadata?

        do {
            let rows = try await connection.query(request.sql, binds, onMetadata: { value in
                metadata = value
            }).get()

            let mappedRows = rows.map(parseRow)
            let columns: [QueryColumn]
            if let first = rows.first {
                columns = first.columnDefinitions.map { column in
                    QueryColumn(
                        name: column.name,
                        databaseTypeName: String(describing: column.columnType),
                        isNullable: true
                    )
                }
            } else {
                columns = []
            }

            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let affectedRows = metadata.flatMap { Int(exactly: $0.affectedRows) }

            return QueryExecutionResult(
                queryID: request.id,
                columns: columns,
                rows: mappedRows,
                affectedRows: affectedRows,
                durationMs: durationMs
            )
        } catch {
            throw Self.mapMySQLError(error)
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
        // Native cancel in MySQLNIO requires a dedicated cancel strategy (e.g. kill query by connection id).
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
            case .integer(let value):
                return value != 0
            default:
                return nil
            }
        }

        var filters: [String] = []
        if request.includeSystemObjects == false {
            filters.append("table_schema NOT IN ('information_schema','mysql','performance_schema','sys')")
        }

        let whereClause = filters.isEmpty ? "" : "WHERE \(filters.joined(separator: " AND "))"
        let sql = """
        SELECT CONCAT(table_schema, '.', table_name) AS object_name, table_type
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
        SELECT CONCAT(table_schema, '.', table_name) AS object_name, column_name, data_type, is_nullable
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
            let indexesSQL = """
            SELECT CONCAT(table_schema, '.', table_name) AS table_path, index_name, column_name
            FROM information_schema.statistics
            \(whereClause)
            ORDER BY table_schema, table_name, index_name, seq_in_index
            """
            let indexResult = try await execute(QueryExecutionRequest(sql: indexesSQL))

            var indexColumnsByPath: [String: [SchemaColumn]] = [:]
            for row in indexResult.rows {
                guard row.count >= 3 else { continue }
                guard let tablePath = stringValue(row[0]), let indexName = stringValue(row[1]), let columnName = stringValue(row[2]) else {
                    continue
                }

                let indexPath = "\(tablePath).\(indexName)"
                indexColumnsByPath[indexPath, default: []].append(
                    SchemaColumn(name: columnName, typeName: "INDEX_COLUMN", isNullable: true)
                )
            }

            let indexObjects = indexColumnsByPath
                .map { path, columns in
                    SchemaObject(path: path, kind: .index, columns: columns)
                }
                .sorted { $0.path < $1.path }

            objects.append(contentsOf: indexObjects)
        }

        var constraintFilters: [String] = []
        if request.includeSystemObjects == false {
            constraintFilters.append("tc.table_schema NOT IN ('information_schema','mysql','performance_schema','sys')")
        }
        let constraintsWhereClause = constraintFilters.isEmpty ? "" : "WHERE \(constraintFilters.joined(separator: " AND "))"

        let constraintsSQL = """
        SELECT
            CONCAT(tc.table_schema, '.', tc.table_name) AS table_path,
            tc.constraint_name,
            tc.constraint_type,
            kcu.column_name
        FROM information_schema.table_constraints tc
        LEFT JOIN information_schema.key_column_usage kcu
            ON tc.constraint_schema = kcu.constraint_schema
            AND tc.table_name = kcu.table_name
            AND tc.constraint_name = kcu.constraint_name
        \(constraintsWhereClause)
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
        let escaped = identifier.replacingOccurrences(of: "`", with: "``")
        return "`\(escaped)`"
    }

    private func convertParameter(_ parameter: QueryParameter) -> MySQLData {
        switch parameter.value {
        case .null:
            return .null
        case .integer(let value):
            if let intValue = Int(exactly: value) {
                return MySQLData(int: intValue)
            }
            return MySQLData(string: String(value))
        case .double(let value):
            return MySQLData(double: value)
        case .string(let value):
            return MySQLData(string: value)
        case .bool(let value):
            return MySQLData(bool: value)
        case .date(let value):
            return MySQLData(date: value)
        case .binary(let value):
            var buffer = ByteBufferAllocator().buffer(capacity: value.count)
            buffer.writeBytes(value)
            return MySQLData(type: .blob, format: .binary, buffer: buffer)
        }
    }

    private func parseRow(_ row: MySQLRow) -> [DatabaseValue] {
        zip(row.columnDefinitions, row.values).map { column, value in
            let data = MySQLData(
                type: column.columnType,
                format: row.format,
                buffer: value,
                isUnsigned: column.flags.contains(.COLUMN_UNSIGNED)
            )
            return parseData(data)
        }
    }

    private func parseData(_ data: MySQLData) -> DatabaseValue {
        guard data.buffer != nil else {
            return .null
        }

        if let intValue = data.int64 {
            return .integer(intValue)
        }
        if let uintValue = data.uint64 {
            if uintValue <= UInt64(Int64.max) {
                return .integer(Int64(uintValue))
            }
            return .string(String(uintValue))
        }
        if let doubleValue = data.double {
            return .double(doubleValue)
        }
        if let dateValue = data.date {
            return .date(dateValue)
        }
        if let boolValue = data.bool,
           data.type == .tiny || data.type == .bit
        {
            return .bool(boolValue)
        }
        if let stringValue = data.string {
            return .string(stringValue)
        }

        var raw = data.buffer
        return .binary(raw.flatMap { Data($0.readableBytesView) } ?? Data())
    }

    private static func shutdown(_ group: MultiThreadedEventLoopGroup) async {
        await withCheckedContinuation { continuation in
            group.shutdownGracefully { _ in
                continuation.resume()
            }
        }
    }

    private static func mapMySQLError(_ error: Error) -> DatabaseAdapterError {
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

        if let mysqlError = error as? MySQLError {
            switch mysqlError {
            case .closed:
                return .networkUnavailable(reason: mysqlError.localizedDescription)
            case .secureConnectionRequired,
                 .unsupportedAuthPlugin,
                 .authPluginDataError,
                 .missingOrInvalidAuthMoreDataStatusTag,
                 .missingOrInvalidAuthPluginInlineCommand,
                 .missingAuthPluginInlineData:
                return .authenticationFailed(reason: mysqlError.localizedDescription)
            case .server(let packet):
                let message = packet.errorMessage
                if message.localizedCaseInsensitiveContains("access denied")
                    || message.localizedCaseInsensitiveContains("authentication")
                {
                    return .authenticationFailed(reason: message)
                }
                return .queryFailed(message: message, sqlState: packet.sqlState)
            default:
                return .queryFailed(message: mysqlError.localizedDescription, sqlState: nil)
            }
        }

        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if message.localizedCaseInsensitiveContains("timed out") {
            return .timeout(seconds: 30)
        }
        return .queryFailed(message: message, sqlState: nil)
    }
}
