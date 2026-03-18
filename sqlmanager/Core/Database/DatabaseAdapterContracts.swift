import Foundation

// Unified contract that every concrete database adapter must implement.
protocol DatabaseAdapter {
    var databaseType: DatabaseType { get }
    var capabilities: DatabaseCapabilities { get }

    func testConnection(_ configuration: DatabaseConnectionConfiguration) async throws
    func openSession(_ configuration: DatabaseConnectionConfiguration) async throws -> any DatabaseSession
}

protocol DatabaseSession: AnyObject {
    var id: UUID { get }
    var databaseType: DatabaseType { get }
    var capabilities: DatabaseCapabilities { get }

    func disconnect() async
    func ping() async throws

    func execute(_ request: QueryExecutionRequest) async throws -> QueryExecutionResult
    func stream(_ request: QueryExecutionRequest) -> AsyncThrowingStream<QueryExecutionEvent, Error>
    func cancel(queryID: UUID) async

    func introspect(_ request: SchemaIntrospectionRequest) async throws -> SchemaSnapshot
    func quoteIdentifier(_ identifier: String) -> String
}

struct DatabaseConnectionConfiguration: Hashable, Codable {
    var profileID: UUID
    var profileName: String
    var databaseType: DatabaseType

    var transport: ConnectionTransport
    var databaseName: String
    var username: String
    var credential: DatabaseCredential

    var useSSL: Bool
    var timeoutSeconds: Int
    var options: [String: String]

    init(
        profileID: UUID,
        profileName: String,
        databaseType: DatabaseType,
        transport: ConnectionTransport,
        databaseName: String,
        username: String,
        credential: DatabaseCredential,
        useSSL: Bool,
        timeoutSeconds: Int,
        options: [String: String] = [:]
    ) {
        self.profileID = profileID
        self.profileName = profileName
        self.databaseType = databaseType
        self.transport = transport
        self.databaseName = databaseName
        self.username = username
        self.credential = credential
        self.useSSL = useSSL
        self.timeoutSeconds = timeoutSeconds
        self.options = options
    }
}

enum ConnectionTransport: Hashable, Codable {
    case hostPort(host: String, port: Int)
    case connectionString(String)
    case unixSocket(path: String)
    case sshTunnel(SSHTunnelConfiguration)
}

struct SSHTunnelConfiguration: Hashable, Codable {
    var sshHost: String
    var sshPort: Int
    var sshUsername: String
    var targetHost: String
    var targetPort: Int
    var privateKeyPath: String?

    init(
        sshHost: String,
        sshPort: Int,
        sshUsername: String,
        targetHost: String,
        targetPort: Int,
        privateKeyPath: String? = nil
    ) {
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.privateKeyPath = privateKeyPath
    }
}

enum DatabaseCredential: Hashable, Codable {
    case none
    case password(String)
    case token(String)
}

struct DatabaseCapabilities: Hashable, Codable {
    var transactions: FeatureSupport
    var queryCancelation: FeatureSupport
    var explainPlan: FeatureSupport
    var schemaIntrospection: FeatureSupport
    var ddlEditing: FeatureSupport
    var parameterizedQueries: FeatureSupport
    var streamingResults: FeatureSupport

    static let minimal = DatabaseCapabilities(
        transactions: .unsupported,
        queryCancelation: .unsupported,
        explainPlan: .unsupported,
        schemaIntrospection: .supported,
        ddlEditing: .unsupported,
        parameterizedQueries: .supported,
        streamingResults: .unsupported
    )
}

enum FeatureSupport: String, Hashable, Codable {
    case supported
    case partial
    case unsupported
}

struct QueryExecutionRequest: Hashable, Codable {
    var id: UUID
    var sql: String
    var parameters: [QueryParameter]
    var limitRows: Int?
    var timeoutSeconds: Int?

    init(
        id: UUID = UUID(),
        sql: String,
        parameters: [QueryParameter] = [],
        limitRows: Int? = nil,
        timeoutSeconds: Int? = nil
    ) {
        self.id = id
        self.sql = sql
        self.parameters = parameters
        self.limitRows = limitRows
        self.timeoutSeconds = timeoutSeconds
    }
}

struct QueryParameter: Hashable, Codable {
    var name: String?
    var value: DatabaseValue

    init(name: String? = nil, value: DatabaseValue) {
        self.name = name
        self.value = value
    }
}

enum DatabaseValue: Hashable, Codable {
    case null
    case integer(Int64)
    case double(Double)
    case string(String)
    case bool(Bool)
    case date(Date)
    case binary(Data)
}

struct QueryExecutionResult: Hashable, Codable {
    var queryID: UUID
    var columns: [QueryColumn]
    var rows: [[DatabaseValue]]
    var affectedRows: Int?
    var durationMs: Int
    var notices: [String]

    init(
        queryID: UUID,
        columns: [QueryColumn],
        rows: [[DatabaseValue]],
        affectedRows: Int? = nil,
        durationMs: Int,
        notices: [String] = []
    ) {
        self.queryID = queryID
        self.columns = columns
        self.rows = rows
        self.affectedRows = affectedRows
        self.durationMs = durationMs
        self.notices = notices
    }
}

struct QueryColumn: Hashable, Codable {
    var name: String
    var databaseTypeName: String
    var isNullable: Bool
}

enum QueryExecutionEvent: Hashable, Codable {
    case header([QueryColumn])
    case rows([[DatabaseValue]])
    case completed(QueryExecutionResult)
}

struct SchemaIntrospectionRequest: Hashable, Codable {
    var includeSystemObjects: Bool
    var includeViews: Bool
    var includeIndexes: Bool

    init(
        includeSystemObjects: Bool = false,
        includeViews: Bool = true,
        includeIndexes: Bool = true
    ) {
        self.includeSystemObjects = includeSystemObjects
        self.includeViews = includeViews
        self.includeIndexes = includeIndexes
    }
}

struct SchemaSnapshot: Hashable, Codable {
    var capturedAt: Date
    var objects: [SchemaObject]

    init(capturedAt: Date = Date(), objects: [SchemaObject]) {
        self.capturedAt = capturedAt
        self.objects = objects
    }
}

struct SchemaObject: Hashable, Codable, Identifiable {
    var id: String { "\(kind.rawValue):\(path)" }
    var path: String
    var kind: SchemaObjectKind
    var columns: [SchemaColumn]
}

struct SchemaColumn: Hashable, Codable {
    var name: String
    var typeName: String
    var isNullable: Bool
}

enum SchemaObjectKind: String, Hashable, Codable {
    case table
    case view
    case index
    case constraint
    case schema
    case database
}

enum DatabaseAdapterError: Error {
    case configurationInvalid(reason: String)
    case authenticationFailed(reason: String?)
    case networkUnavailable(reason: String?)
    case timeout(seconds: Int)
    case queryFailed(message: String, sqlState: String?)
    case unsupportedFeature(feature: String)
    case cancelled
}

extension DatabaseAdapterError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .configurationInvalid(let reason):
            return "Configuration is invalid: \(reason)"
        case .authenticationFailed(let reason):
            if let reason, reason.isEmpty == false {
                return "Authentication failed: \(reason)"
            }
            return "Authentication failed"
        case .networkUnavailable(let reason):
            if let reason, reason.isEmpty == false {
                return "Network is unavailable: \(reason)"
            }
            return "Network is unavailable"
        case .timeout(let seconds):
            return "Operation timed out after \(seconds) seconds"
        case .queryFailed(let message, let sqlState):
            if let sqlState, sqlState.isEmpty == false {
                return "Query failed [\(sqlState)]: \(message)"
            }
            return "Query failed: \(message)"
        case .unsupportedFeature(let feature):
            return "This database does not support \(feature)"
        case .cancelled:
            return "Operation cancelled"
        }
    }
}
