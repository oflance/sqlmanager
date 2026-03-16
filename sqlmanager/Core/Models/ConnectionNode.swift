//
//  ConnectionNode.swift
//  sqlmanager
//

import SwiftUI

struct ConnectionNode: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var kind: NodeKind
    var icon: String
    var color: NodeColor
    var databaseType: DatabaseType
    var connectionMethod: ConnectionMethod
    var host: String
    var port: String
    var database: String
    var username: String
    var useSSL: Bool
    var timeoutSeconds: Int
    var children: [ConnectionNode]

    init(
        id: UUID = UUID(),
        name: String,
        kind: NodeKind,
        icon: String,
        color: NodeColor,
        databaseType: DatabaseType = .postgresql,
        connectionMethod: ConnectionMethod = .hostPort,
        host: String = "localhost",
        port: String = "5432",
        database: String = "",
        username: String = "",
        useSSL: Bool = true,
        timeoutSeconds: Int = 15,
        children: [ConnectionNode] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.icon = icon
        self.color = color
        self.databaseType = databaseType
        self.connectionMethod = connectionMethod
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.useSSL = useSSL
        self.timeoutSeconds = timeoutSeconds
        self.children = children
    }

    static let empty = ConnectionNode(
        name: "Unknown",
        kind: .folder,
        icon: "questionmark.folder",
        color: .gray
    )

    var childNodes: [ConnectionNode]? {
        children.isEmpty ? nil : children
    }
}

enum NodeKind: String, Hashable, Codable {
    case folder = "Folder"
    case profile = "Profile"
}

enum DatabaseType: String, CaseIterable, Identifiable, Hashable, Codable {
    case postgresql = "PostgreSQL"
    case mysql = "MySQL"
    case sqlite = "SQLite"
    case mssql = "SQL Server"
    case oracle = "Oracle"

    var id: String { rawValue }

    func localized(language: AppLanguage) -> String {
        switch self {
        case .postgresql: return L10n.tr("db.postgresql", language: language)
        case .mysql: return L10n.tr("db.mysql", language: language)
        case .sqlite: return L10n.tr("db.sqlite", language: language)
        case .mssql: return L10n.tr("db.mssql", language: language)
        case .oracle: return L10n.tr("db.oracle", language: language)
        }
    }
}

enum ConnectionMethod: String, CaseIterable, Identifiable, Hashable, Codable {
    case hostPort = "Host + Port"
    case connectionString = "Connection String"
    case sshTunnel = "SSH Tunnel"
    case socket = "Local Socket"

    var id: String { rawValue }

    func localized(language: AppLanguage) -> String {
        switch self {
        case .hostPort: return L10n.tr("method.host_port", language: language)
        case .connectionString: return L10n.tr("method.connection_string", language: language)
        case .sshTunnel: return L10n.tr("method.ssh_tunnel", language: language)
        case .socket: return L10n.tr("method.socket", language: language)
        }
    }
}

enum NodeColor: String, CaseIterable, Identifiable, Hashable, Codable {
    case defaultColor
    case red
    case orange
    case yellow
    case green
    case blue
    case indigo
    case purple
    case pink
    case gray

    var id: String { rawValue }

    func localized(language: AppLanguage) -> String {
        switch self {
        case .defaultColor: return L10n.tr("color.default", language: language)
        case .red: return L10n.tr("color.red", language: language)
        case .orange: return L10n.tr("color.orange", language: language)
        case .yellow: return L10n.tr("color.yellow", language: language)
        case .green: return L10n.tr("color.green", language: language)
        case .blue: return L10n.tr("color.blue", language: language)
        case .indigo: return L10n.tr("color.indigo", language: language)
        case .purple: return L10n.tr("color.purple", language: language)
        case .pink: return L10n.tr("color.pink", language: language)
        case .gray: return L10n.tr("color.gray", language: language)
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .defaultColor: return .primary
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }
}
