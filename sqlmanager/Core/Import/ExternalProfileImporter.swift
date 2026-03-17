//
//  ExternalProfileImporter.swift
//  sqlmanager
//

import Foundation

struct ProfileImportBatchResult {
    let source: ProfileImportSource
    let importedItems: [ImportedProfileItem]
    let discoveredFiles: [URL]
    let processedFileCount: Int
    let duplicateItemsInSource: Int
    let plaintextPasswordCandidates: Int
    let encryptedPasswordCount: Int
    let errors: [String]
}

struct ImportedProfileItem {
    let node: ConnectionNode
    let folderPath: [String]
    let plaintextPassword: String?
    let hasEncryptedPassword: Bool
}

enum ExternalProfileImporter {
    static func importFromDefaultLocations(for source: ProfileImportSource) -> ProfileImportBatchResult {
        let fileManager = FileManager.default
        let discovered = source.defaultLocations(fileManager: fileManager).filter { fileManager.fileExists(atPath: $0.path) }
        return importFromFiles(discovered, source: source)
    }

    static func importFromFile(_ url: URL, source: ProfileImportSource) -> ProfileImportBatchResult {
        importFromFiles([url], source: source)
    }

    private static func importFromFiles(_ urls: [URL], source: ProfileImportSource) -> ProfileImportBatchResult {
        var profiles: [ImportedProfile] = []
        var errors: [String] = []

        for url in urls {
            do {
                let parsedProfiles: [ImportedProfile]
                switch source {
                case .heidiSQL:
                    parsedProfiles = try parseHeidiINI(at: url)
                case .sequelAce, .sequelPro:
                    parsedProfiles = try parseSequelFavorites(at: url, source: source)
                }
                profiles.append(contentsOf: parsedProfiles)
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        let deduplicatedProfiles = deduplicate(profiles)
        let plaintextPasswords = deduplicatedProfiles.filter { $0.plaintextPassword?.isEmpty == false }.count
        let encryptedPasswords = deduplicatedProfiles.filter(\.hasEncryptedPassword).count
        return ProfileImportBatchResult(
            source: source,
            importedItems: deduplicatedProfiles.map { profile in
                ImportedProfileItem(
                    node: makeNode(from: profile),
                    folderPath: profile.folderPath,
                    plaintextPassword: profile.plaintextPassword,
                    hasEncryptedPassword: profile.hasEncryptedPassword
                )
            },
            discoveredFiles: urls,
            processedFileCount: urls.count,
            duplicateItemsInSource: max(0, profiles.count - deduplicatedProfiles.count),
            plaintextPasswordCandidates: plaintextPasswords,
            encryptedPasswordCount: encryptedPasswords,
            errors: errors
        )
    }

    private struct ImportedProfile {
        let name: String
        let databaseType: DatabaseType
        let host: String
        let port: String
        let database: String
        let username: String
        let useSSL: Bool
        let connectionMethod: ConnectionMethod
        let timeoutSeconds: Int
        let folderPath: [String]
        let plaintextPassword: String?
        let hasEncryptedPassword: Bool
    }

    private enum ImportError: LocalizedError {
        case unreadableData
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .unreadableData:
                return "Unreadable file data"
            case .unsupportedFormat:
                return "Unsupported file format"
            }
        }
    }

    private static func parseHeidiINI(at url: URL) throws -> [ImportedProfile] {
        guard let raw = try String(data: Data(contentsOf: url), encoding: .utf8) else {
            throw ImportError.unreadableData
        }

        if raw.contains("<|||>") {
            let exportedProfiles = parseHeidiExportFormat(raw)
            if exportedProfiles.isEmpty == false {
                return exportedProfiles
            }
        }

        var sections: [String: [String: String]] = [:]
        var currentSection: String?

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }
            guard let section = currentSection, let separatorIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            sections[section, default: [:]][key] = value
        }

        let serverSections = sections.filter { section, _ in
            let lowered = section.lowercased()
            return lowered.contains("servers\\") || lowered.contains("servers/")
        }

        return serverSections.compactMap { section, values in
            let name = section.components(separatedBy: CharacterSet(charactersIn: "\\/")).last?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = (name?.isEmpty == false ? name! : "HeidiSQL")
            let dbType = databaseType(from: values["Library"], fallback: values["NetType"] ?? values["Provider"] ?? values["Port"])
            let host = values["Hostname"].flatMap(normalizedValue(_:)) ?? "localhost"
            let port = normalizedValue(values["Port"]) ?? defaultPort(for: dbType)
            let database = normalizedValue(values["Database"]) ?? ""
            let username = normalizedValue(values["User"]) ?? ""
            let useSSL = boolValue(values["SSL_Active"]) ?? boolValue(values["UseSSL"]) ?? boolValue(values["SSL"]) ?? false
            let folderPath = heidiFolderPath(from: section.components(separatedBy: CharacterSet(charactersIn: "\\/")))
            let passwordParse = parseHeidiPassword(values["Password"])

            return ImportedProfile(
                name: finalName,
                databaseType: dbType,
                host: host,
                port: port,
                database: database,
                username: username,
                useSSL: useSSL,
                connectionMethod: .hostPort,
                timeoutSeconds: 15,
                folderPath: folderPath,
                plaintextPassword: passwordParse.plaintext,
                hasEncryptedPassword: passwordParse.encrypted
            )
        }
    }

    private static func parseSequelFavorites(at url: URL, source: ProfileImportSource) throws -> [ImportedProfile] {
        let data = try Data(contentsOf: url)
        let plistObject = try PropertyListSerialization.propertyList(from: data, format: nil)
        var dictionaries: [[String: Any]] = []
        collectDictionaries(in: plistObject, result: &dictionaries)

        let favorites = dictionaries.filter(isLikelyFavorite)
        if favorites.isEmpty {
            throw ImportError.unsupportedFormat
        }

        return favorites.compactMap { favorite in
            let name = stringValue(for: ["Name", "name", "Nickname", "nickname"], in: favorite) ?? "\(source.displayName) Profile"
            let host = stringValue(for: ["Host", "host", "Hostname", "hostname"], in: favorite)
                ?? stringValue(for: ["Socket", "socket"], in: favorite)
                ?? "localhost"
            let database = stringValue(for: ["Database", "database"], in: favorite) ?? ""
            let username = stringValue(for: ["User", "user", "Username", "username"], in: favorite) ?? ""
            let rawPort = stringValue(for: ["Port", "port"], in: favorite)
            let dbType = databaseType(from: stringValue(for: ["Type", "type", "databaseType"], in: favorite), fallback: source.displayName)
            let useSSL = boolValue(anyValue(for: ["useSSL", "UseSSL", "SSL"], in: favorite)) ?? false
            let plaintextPassword = stringValue(for: ["Password", "password"], in: favorite)

            return ImportedProfile(
                name: name,
                databaseType: dbType,
                host: host,
                port: rawPort ?? defaultPort(for: dbType),
                database: database,
                username: username,
                useSSL: useSSL,
                connectionMethod: .hostPort,
                timeoutSeconds: 15,
                folderPath: [],
                plaintextPassword: plaintextPassword,
                hasEncryptedPassword: false
            )
        }
    }

    private static func parseHeidiExportFormat(_ raw: String) -> [ImportedProfile] {
        var sessions: [String: [String: String]] = [:]
        var folderSessions = Set<String>()

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let parts = trimmed.components(separatedBy: "<|||>")
            if parts.count < 3 { continue }

            let keyPath = parts[0]
            guard keyPath.hasPrefix("Servers\\") else { continue }

            let value = parts[2]
            let keySegments = keyPath.components(separatedBy: "\\")
            guard keySegments.count >= 3 else { continue }

            let property = keySegments.last ?? ""
            let sessionPath = keySegments.dropLast().joined(separator: "\\")

            if property == "Folder", boolValue(value) == true {
                folderSessions.insert(sessionPath)
            }

            sessions[sessionPath, default: [:]][property] = value
        }

        var result: [ImportedProfile] = []
        for (sessionPath, properties) in sessions {
            if folderSessions.contains(sessionPath) { continue }
            if properties["Host"] == nil && properties["Hostname"] == nil { continue }

            let sessionName = sessionPath.components(separatedBy: "\\").last?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = (sessionName?.isEmpty == false ? sessionName! : "HeidiSQL")
            let folderPath = heidiFolderPath(from: sessionPath.components(separatedBy: "\\"))
            let dbType = databaseType(from: properties["Library"], fallback: properties["NetType"] ?? properties["Provider"] ?? properties["Port"])
            let host = normalizedValue(properties["Host"]) ?? normalizedValue(properties["Hostname"]) ?? "localhost"
            let port = normalizedValue(properties["Port"]) ?? defaultPort(for: dbType)
            let database = primaryDatabaseName(from: properties["Databases"]) ?? normalizedValue(properties["Database"]) ?? ""
            let username = normalizedValue(properties["User"]) ?? ""
            let useSSL = boolValue(properties["SSL_Active"]) ?? boolValue(properties["UseSSL"]) ?? boolValue(properties["SSL"]) ?? false
            let timeout = Int(normalizedValue(properties["QueryTimeout"]) ?? "") ?? 15
            let hasSshTunnel = (normalizedValue(properties["SSHtunnelHost"])?.isEmpty == false)
            let method: ConnectionMethod = hasSshTunnel ? .sshTunnel : .hostPort
            let passwordParse = parseHeidiPassword(properties["Password"])

            result.append(
                ImportedProfile(
                    name: finalName,
                    databaseType: dbType,
                    host: host,
                    port: port,
                    database: database,
                    username: username,
                    useSSL: useSSL,
                    connectionMethod: method,
                    timeoutSeconds: max(5, min(timeout, 120)),
                    folderPath: folderPath,
                    plaintextPassword: passwordParse.plaintext,
                    hasEncryptedPassword: passwordParse.encrypted
                )
            )
        }

        return result
    }

    private static func makeNode(from profile: ImportedProfile) -> ConnectionNode {
        ConnectionNode(
            name: profile.name,
            kind: .profile,
            icon: "cylinder",
            color: .green,
            databaseType: profile.databaseType,
            connectionMethod: profile.connectionMethod,
            host: profile.host,
            port: profile.port,
            database: profile.database,
            username: profile.username,
            useSSL: profile.useSSL,
            timeoutSeconds: profile.timeoutSeconds
        )
    }

    nonisolated private static func deduplicate(_ profiles: [ImportedProfile]) -> [ImportedProfile] {
        var seen = Set<String>()
        var unique: [ImportedProfile] = []

        for profile in profiles {
            let key = [
                profile.folderPath.joined(separator: "/"),
                profile.name,
                profile.databaseType.rawValue,
                profile.host,
                profile.port,
                profile.database,
                profile.username
            ].joined(separator: "|")
            if seen.insert(key).inserted {
                unique.append(profile)
            }
        }

        return unique
    }

    nonisolated private static func collectDictionaries(in object: Any, result: inout [[String: Any]]) {
        if let dictionary = object as? [String: Any] {
            result.append(dictionary)
            for value in dictionary.values {
                collectDictionaries(in: value, result: &result)
            }
            return
        }

        if let array = object as? [Any] {
            for item in array {
                collectDictionaries(in: item, result: &result)
            }
        }
    }

    nonisolated private static func isLikelyFavorite(_ dictionary: [String: Any]) -> Bool {
        let hasHost = stringValue(for: ["Host", "host", "Hostname", "hostname", "Socket", "socket"], in: dictionary) != nil
        let hasIdentity = stringValue(for: ["Name", "name", "Nickname", "nickname"], in: dictionary) != nil
            || stringValue(for: ["Database", "database"], in: dictionary) != nil
            || stringValue(for: ["User", "user", "Username", "username"], in: dictionary) != nil
        return hasHost && hasIdentity
    }

    nonisolated private static func stringValue(for keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            if let value = dictionary[key] {
                if let text = normalizedValue(value) {
                    return text
                }
            }
        }

        let lowered = Set(keys.map { $0.lowercased() })
        for (key, value) in dictionary where lowered.contains(key.lowercased()) {
            if let text = normalizedValue(value) {
                return text
            }
        }

        return nil
    }

    nonisolated private static func anyValue(for keys: [String], in dictionary: [String: Any]) -> Any? {
        for key in keys {
            if let value = dictionary[key] { return value }
        }
        let lowered = Set(keys.map { $0.lowercased() })
        for (key, value) in dictionary where lowered.contains(key.lowercased()) {
            return value
        }
        return nil
    }

    nonisolated private static func normalizedValue(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    nonisolated private static func boolValue(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    nonisolated private static func databaseType(from rawType: String?, fallback: String?) -> DatabaseType {
        let text = "\(rawType ?? "") \(fallback ?? "")".lowercased()
        if text.contains("postgre") || text.contains("pgsql") {
            return .postgresql
        }
        if text.contains("sqlite") {
            return .sqlite
        }
        if text.contains("mssql") || text.contains("sql server") || text.contains("sqlsrv") {
            return .mssql
        }
        if text.contains("oracle") {
            return .oracle
        }
        return .mysql
    }

    nonisolated private static func defaultPort(for databaseType: DatabaseType) -> String {
        switch databaseType {
        case .postgresql: return "5432"
        case .mysql: return "3306"
        case .sqlite: return ""
        case .mssql: return "1433"
        case .oracle: return "1521"
        }
    }

    nonisolated private static func primaryDatabaseName(from raw: String?) -> String? {
        guard let raw = normalizedValue(raw) else { return nil }
        for separator in [",", ";", "|"] {
            if let first = raw.components(separatedBy: separator).first {
                let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }
        return raw
    }

    nonisolated private static func heidiFolderPath(from segments: [String]) -> [String] {
        guard segments.count >= 3 else { return [] }

        let normalized = segments.filter { $0.isEmpty == false }
        guard normalized.count >= 3 else { return [] }
        let head = normalized[0].lowercased()
        guard head == "servers" else { return [] }

        return Array(normalized.dropFirst().dropLast())
    }

    nonisolated private static func parseHeidiPassword(_ raw: String?) -> (plaintext: String?, encrypted: Bool) {
        guard let value = normalizedValue(raw) else {
            return (nil, false)
        }

        let decoded = heidiDecode(value)
        if decoded.isEmpty == false {
            return (decoded, false)
        }

        let charset = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        let isHexLike = value.rangeOfCharacter(from: charset.inverted) == nil
        if isHexLike && value.count >= 8 && value.count.isMultiple(of: 2) {
            return (nil, true)
        }

        return (value, false)
    }

    nonisolated private static func heidiDecode(_ value: String) -> String {
        guard let lastChar = value.last,
              let shift = Int(String(lastChar)) else {
            return ""
        }

        let hexPart = String(value.dropLast())

        guard hexPart.count % 2 == 0 else {
            return ""
        }

        var result = ""
        var index = hexPart.startIndex

        while index < hexPart.endIndex {
            let nextIndex = hexPart.index(index, offsetBy: 2)
            let byteString = String(hexPart[index..<nextIndex])

            guard let byteValue = Int(byteString, radix: 16) else {
                return ""
            }

            let decodedValue = byteValue - shift
            guard let scalar = UnicodeScalar(decodedValue) else {
                return ""
            }

            result.append(Character(scalar))
            index = nextIndex
        }

        return result
    }
}
