# Database Adapter Interface

## Purpose
This contract defines a single integration surface for all supported database engines.
UI and app state work with unified models, while each adapter handles engine-specific details.

## Core Contracts
- `DatabaseAdapter`
  - `testConnection(_:)`
  - `openSession(_:)`
- `DatabaseSession`
  - lifecycle: `ping()`, `disconnect()`
  - query: `execute(_:)`, `stream(_:)`, `cancel(queryID:)`
  - schema: `introspect(_:)`
  - SQL dialect utility: `quoteIdentifier(_:)`

## Unified Data Types
- Connection: `DatabaseConnectionConfiguration`, `ConnectionTransport`, `DatabaseCredential`
- Query: `QueryExecutionRequest`, `QueryParameter`, `QueryExecutionResult`, `QueryExecutionEvent`
- Schema: `SchemaIntrospectionRequest`, `SchemaSnapshot`, `SchemaObject`
- Errors: `DatabaseAdapterError` (normalized to app-friendly error messages)

## Capability Matrix (target defaults)

| Engine      | Transactions | Cancel Query | Explain Plan | Introspection | DDL Editing | Parameters | Streaming |
|-------------|--------------|--------------|--------------|---------------|-------------|------------|-----------|
| PostgreSQL  | supported    | supported    | supported    | supported     | supported   | supported  | supported |
| MySQL       | supported    | partial      | supported    | supported     | supported   | supported  | partial   |
| SQLite      | supported    | unsupported  | partial      | supported     | supported   | supported  | unsupported |
| SQL Server  | supported    | supported    | supported    | supported     | supported   | supported  | partial   |
| Oracle      | supported    | partial      | supported    | supported     | supported   | supported  | partial   |

Use `DatabaseCapabilities` in each adapter to expose actual support and gate UI actions.

## Mapping from existing profile model
`ConnectionNode.asDatabaseConnectionConfiguration(...)` is the current bridge from saved profile UI data to adapter-ready config.

Current temporary assumptions:
- `ConnectionMethod.connectionString` stores connection string in `ConnectionNode.host`.
- `ConnectionMethod.socket` stores socket path in `ConnectionNode.host`.
- SSH tunnel currently uses default `sshPort = 22` and local tunnel target host `127.0.0.1`.

## Current implementation status
Implemented:
1. `AdapterRegistry` (`DatabaseType -> DatabaseAdapter`)
2. `ConnectionManager` actor for session lifecycle
3. `ContentView.toggleConnection(...)` and `runQuery(...)` wired to async manager calls
4. `SQLiteAdapter` + `SQLiteSession` (connect, ping, execute, introspect)
5. `PostgreSQLAdapter` + `PostgreSQLSession` via native `PostgresNIO` driver (connect, ping, execute, introspect)
6. `MySQLAdapter` + `MySQLSession` via native `MySQLNIO` driver (connect, ping, execute, introspect)

Pending:
1. Add native query cancellation strategy per engine (cancel token/connection kill).
2. Implement MSSQL/Oracle adapters
3. Add integration tests for shared scenarios across all adapters
