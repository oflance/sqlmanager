import Foundation
import Network

actor ConnectionManager {
    private let adapterRegistry: AdapterRegistry
    private var sessionsByTabID: [UUID: any DatabaseSession] = [:]

    init(adapterRegistry: AdapterRegistry) {
        self.adapterRegistry = adapterRegistry
    }

    func connect(tabID: UUID, profile: ConnectionNode, credential: DatabaseCredential = .none) async throws {
        let configuration = await profile.asDatabaseConnectionConfiguration(credential: credential)
        let adapter = try await adapterRegistry.adapter(for: configuration.databaseType)

        try await adapter.testConnection(configuration)
        let session = try await adapter.openSession(configuration)

        if let existing = sessionsByTabID[tabID] {
            await existing.disconnect()
        }
        sessionsByTabID[tabID] = session
    }

    func testConnection(profile: ConnectionNode, credential: DatabaseCredential = .none) async throws {
        let configuration = await profile.asDatabaseConnectionConfiguration(credential: credential)
        let adapter = try await adapterRegistry.adapter(for: configuration.databaseType)
        try await adapter.testConnection(configuration)
    }

    func disconnect(tabID: UUID) async {
        guard let session = sessionsByTabID.removeValue(forKey: tabID) else { return }
        await session.disconnect()
    }

    func disconnectAll() async {
        let sessions = sessionsByTabID.values
        sessionsByTabID.removeAll()
        for session in sessions {
            await session.disconnect()
        }
    }

    func ping(tabID: UUID) async throws {
        guard let session = sessionsByTabID[tabID] else {
            throw DatabaseAdapterError.configurationInvalid(reason: "No active session")
        }
        try await session.ping()
    }

    func execute(tabID: UUID, sql: String) async throws -> QueryExecutionResult {
        guard let session = sessionsByTabID[tabID] else {
            throw DatabaseAdapterError.configurationInvalid(reason: "No active session")
        }
        return try await session.execute(QueryExecutionRequest(sql: sql))
    }

    func introspect(
        tabID: UUID,
        request: SchemaIntrospectionRequest = SchemaIntrospectionRequest()
    ) async throws -> SchemaSnapshot {
        guard let session = sessionsByTabID[tabID] else {
            throw DatabaseAdapterError.configurationInvalid(reason: "No active session")
        }
        return try await session.introspect(request)
    }

    func hasSession(tabID: UUID) -> Bool {
        sessionsByTabID[tabID] != nil
    }

    func testTCP(profile: ConnectionNode) async throws -> String {
        let configuration = await profile.asDatabaseConnectionConfiguration()
        switch configuration.transport {
        case .hostPort(let host, let port):
            try TCPConnectivityProbe.connect(host: host, port: port, timeoutSeconds: configuration.timeoutSeconds)
            return "\(host):\(port)"
        case .sshTunnel(let ssh):
            try TCPConnectivityProbe.connect(
                host: ssh.targetHost,
                port: ssh.targetPort,
                timeoutSeconds: configuration.timeoutSeconds
            )
            return "\(ssh.targetHost):\(ssh.targetPort) (SSH target)"
        case .connectionString:
            throw DatabaseAdapterError.unsupportedFeature(feature: "TCP test for connection string profiles")
        case .unixSocket:
            throw DatabaseAdapterError.unsupportedFeature(feature: "TCP test for local socket profiles")
        }
    }
}

private enum TCPConnectivityProbe {
    static func connect(host: String, port: Int, timeoutSeconds: Int) throws {
        final class ProbeState: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var completed = false
            private(set) var error: Error?

            func complete(with error: Error?) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard completed == false else { return false }
                completed = true
                self.error = error
                return true
            }
        }

        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedHost.isEmpty == false else {
            throw DatabaseAdapterError.configurationInvalid(reason: "Host is required for TCP test")
        }
        guard (1...65535).contains(port) else {
            throw DatabaseAdapterError.configurationInvalid(reason: "Port must be between 1 and 65535")
        }
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw DatabaseAdapterError.configurationInvalid(reason: "Invalid port value")
        }

        let connection = NWConnection(host: NWEndpoint.Host(normalizedHost), port: endpointPort, using: .tcp)
        let queue = DispatchQueue(label: "sqlmanager.tcp.probe.\(UUID().uuidString)")
        let timeout = max(timeoutSeconds, 1)
        let semaphore = DispatchSemaphore(value: 0)
        let probeState = ProbeState()

        connection.stateUpdateHandler = { connectionState in
            switch connectionState {
            case .ready:
                if probeState.complete(with: nil) {
                    semaphore.signal()
                }
            case .failed(let error):
                if probeState.complete(with: error) {
                    semaphore.signal()
                }
            case .cancelled:
                if probeState.complete(with: nil) {
                    semaphore.signal()
                }
            default:
                break
            }
        }

        connection.start(queue: queue)
        let waitResult = semaphore.wait(timeout: .now() + .seconds(timeout))
        connection.stateUpdateHandler = nil
        connection.cancel()

        if waitResult == .timedOut {
            throw DatabaseAdapterError.timeout(seconds: timeout)
        }
        if let error = probeState.error {
            throw error
        }
    }
}
