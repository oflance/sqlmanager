import Foundation

struct AdapterRegistry {
    private let adapters: [DatabaseType: any DatabaseAdapter]

    init(adapters: [any DatabaseAdapter]) {
        var map: [DatabaseType: any DatabaseAdapter] = [:]
        for adapter in adapters {
            map[adapter.databaseType] = adapter
        }
        self.adapters = map
    }

    func adapter(for databaseType: DatabaseType) throws -> any DatabaseAdapter {
        guard let adapter = adapters[databaseType] else {
            throw DatabaseAdapterError.unsupportedFeature(feature: "Adapter for \(databaseType.rawValue)")
        }
        return adapter
    }

    static let `default` = AdapterRegistry(
        adapters: [
            PostgreSQLAdapter(),
            SQLiteAdapter(),
            MySQLAdapter(),
            UnavailableDatabaseAdapter(databaseType: .mssql),
            UnavailableDatabaseAdapter(databaseType: .oracle)
        ]
    )
}

private struct UnavailableDatabaseAdapter: DatabaseAdapter {
    let databaseType: DatabaseType
    let capabilities: DatabaseCapabilities = .minimal

    func testConnection(_ configuration: DatabaseConnectionConfiguration) async throws {
        throw DatabaseAdapterError.unsupportedFeature(feature: "\(databaseType.rawValue) adapter is not implemented yet")
    }

    func openSession(_ configuration: DatabaseConnectionConfiguration) async throws -> any DatabaseSession {
        throw DatabaseAdapterError.unsupportedFeature(feature: "\(databaseType.rawValue) adapter is not implemented yet")
    }
}
