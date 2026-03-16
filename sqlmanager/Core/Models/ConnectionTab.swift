//
//  ConnectionTab.swift
//  sqlmanager
//

import SwiftUI

enum RootTab: Hashable, Codable {
    case profiles
    case connection(UUID)

    private enum CodingKeys: String, CodingKey {
        case type
        case connectionID
    }

    private enum TabType: String, Codable {
        case profiles
        case connection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(TabType.self, forKey: .type) {
        case .profiles:
            self = .profiles
        case .connection:
            let id = try container.decode(UUID.self, forKey: .connectionID)
            self = .connection(id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .profiles:
            try container.encode(TabType.profiles, forKey: .type)
        case .connection(let id):
            try container.encode(TabType.connection, forKey: .type)
            try container.encode(id, forKey: .connectionID)
        }
    }
}

struct ConnectionTab: Identifiable, Hashable, Codable {
    let id: UUID
    let profileID: UUID
    var title: String
    var databaseType: DatabaseType
    var connectionMethod: ConnectionMethod
    var useSSL: Bool
    var timeoutSeconds: Int
    var status: ConnectionStatus

    init(
        id: UUID = UUID(),
        profileID: UUID,
        title: String,
        databaseType: DatabaseType,
        connectionMethod: ConnectionMethod,
        useSSL: Bool,
        timeoutSeconds: Int,
        status: ConnectionStatus
    ) {
        self.id = id
        self.profileID = profileID
        self.title = title
        self.databaseType = databaseType
        self.connectionMethod = connectionMethod
        self.useSSL = useSSL
        self.timeoutSeconds = timeoutSeconds
        self.status = status
    }

    static let empty = ConnectionTab(
        profileID: UUID(),
        title: "Unknown",
        databaseType: .postgresql,
        connectionMethod: .hostPort,
        useSSL: true,
        timeoutSeconds: 15,
        status: .disconnected
    )

    func previewText(language: AppLanguage) -> String {
        let ssl = useSSL ? L10n.tr("value.enabled", language: language) : L10n.tr("value.disabled", language: language)
        return "\(databaseType.localized(language: language)) via \(connectionMethod.localized(language: language))\n\(L10n.tr("field.ssl", language: language)): \(ssl), \(L10n.tr("field.timeout", language: language)): \(timeoutSeconds)s\n\(L10n.tr("label.status", language: language)): \(status.localized(language: language))"
    }
}

enum ConnectionStatus: String, Hashable, Codable {
    case connecting = "Connecting"
    case connected = "Connected"
    case disconnected = "Disconnected"

    func localized(language: AppLanguage) -> String {
        switch self {
        case .connecting: return L10n.tr("status.connecting", language: language)
        case .connected: return L10n.tr("status.connected", language: language)
        case .disconnected: return L10n.tr("status.disconnected", language: language)
        }
    }

    var color: Color {
        switch self {
        case .connecting: return .blue
        case .connected: return .green
        case .disconnected: return .orange
        }
    }
}
