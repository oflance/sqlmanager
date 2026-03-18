import Foundation

extension ConnectionNode {
    func asDatabaseConnectionConfiguration(credential: DatabaseCredential = .none) -> DatabaseConnectionConfiguration {
        DatabaseConnectionConfiguration(
            profileID: id,
            profileName: name,
            databaseType: databaseType,
            transport: connectionTransport,
            databaseName: database,
            username: username,
            credential: credential,
            useSSL: useSSL,
            timeoutSeconds: timeoutSeconds
        )
    }

    private var connectionTransport: ConnectionTransport {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        switch connectionMethod {
        case .hostPort:
            return .hostPort(host: normalizedHost.isEmpty ? "localhost" : normalizedHost, port: parsedPort)
        case .connectionString:
            // Until a dedicated field is introduced, we reuse `host` to store connection strings.
            return .connectionString(normalizedHost)
        case .socket:
            // Until a dedicated field is introduced, we reuse `host` to store socket path.
            return .unixSocket(path: normalizedHost)
        case .sshTunnel:
            return .sshTunnel(
                SSHTunnelConfiguration(
                    sshHost: normalizedHost.isEmpty ? "localhost" : normalizedHost,
                    sshPort: 22,
                    sshUsername: username,
                    targetHost: "127.0.0.1",
                    targetPort: parsedPort
                )
            )
        }
    }

    private var parsedPort: Int {
        let value = Int(port) ?? defaultPort
        return max(value, 1)
    }

    private var defaultPort: Int {
        switch databaseType {
        case .postgresql:
            return 5432
        case .mysql:
            return 3306
        case .sqlite:
            return 1
        case .mssql:
            return 1433
        case .oracle:
            return 1521
        }
    }
}
