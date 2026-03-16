import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct WorkspaceSnapshot: Codable {
    var openTabs: [ConnectionTab]
    var selectedRootTab: RootTab
    var selectedNodeID: UUID?
    var isSettingsOpen: Bool
}

private struct PersistenceEnvelope<T: Codable>: Codable {
    let schemaVersion: Int
    let savedAt: Date
    let payload: T
}

final class SQLitePersistence {
    private let schemaVersion = 1
    private let fileManager: FileManager
    private let databaseURL: URL
    private var db: OpaquePointer?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("sqlmanager", isDirectory: true)
        databaseURL = baseDir.appendingPathComponent("sqlmanager.sqlite", isDirectory: false)
        
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        openDatabase()
        createSchemaIfNeeded()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    func loadTree() -> [ConnectionNode]? {
        loadState(forKey: "tree")
    }

    func saveTree(_ tree: [ConnectionNode]) throws {
        try saveState(tree, forKey: "tree")
    }

    func loadWorkspace() -> WorkspaceSnapshot? {
        loadState(forKey: "workspace")
    }

    func saveWorkspace(_ snapshot: WorkspaceSnapshot) throws {
        try saveState(snapshot, forKey: "workspace")
    }

    private func openDatabase() {
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else { return }
        sqlite3_busy_timeout(db, 1500)
    }

    private func createSchemaIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS app_state (
            key TEXT PRIMARY KEY,
            value BLOB NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS query_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            profile_id TEXT,
            query_text TEXT NOT NULL,
            duration_ms INTEGER,
            success INTEGER NOT NULL DEFAULT 1,
            executed_at REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_query_history_executed_at
        ON query_history(executed_at DESC);
        """
        _ = sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func saveState<T: Codable>(_ value: T, forKey key: String) throws {
        let envelope = PersistenceEnvelope(schemaVersion: schemaVersion, savedAt: Date(), payload: value)
        let data = try JSONEncoder().encode(envelope)

        let sql = "INSERT OR REPLACE INTO app_state(key, value, updated_at) VALUES(?, ?, ?);"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        _ = key.withCString { keyCString in
            sqlite3_bind_text(stmt, 1, keyCString, -1, SQLITE_TRANSIENT)
        }
        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                sqlite3_bind_blob(stmt, 2, baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
        }
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
        _ = sqlite3_step(stmt)
    }

    private func loadState<T: Codable>(forKey key: String) -> T? {
        let sql = "SELECT value FROM app_state WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        _ = key.withCString { keyCString in
            sqlite3_bind_text(stmt, 1, keyCString, -1, SQLITE_TRANSIENT)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let raw = sqlite3_column_blob(stmt, 0) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, 0))
        let data = Data(bytes: raw, count: count)
        guard let envelope = try? JSONDecoder().decode(PersistenceEnvelope<T>.self, from: data) else { return nil }
        guard envelope.schemaVersion == schemaVersion else { return nil }
        return envelope.payload
    }
}
