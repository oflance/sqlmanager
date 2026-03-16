//
//  ProfileImportSource.swift
//  sqlmanager
//

import Foundation
import UniformTypeIdentifiers

enum ProfileImportSource: String, CaseIterable, Identifiable {
    case heidiSQL
    case sequelAce
    case sequelPro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heidiSQL: return "HeidiSQL"
        case .sequelAce: return "Sequel Ace"
        case .sequelPro: return "Sequel Pro"
        }
    }

    var menuTitle: String {
        "From \(displayName)..."
    }

    var importFolderName: String {
        "Imported from \(displayName)"
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .heidiSQL:
            return [.plainText, .text]
        case .sequelAce, .sequelPro:
            return [.propertyList, .xml, .data]
        }
    }

    func defaultLocations(fileManager: FileManager = .default) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        switch self {
        case .heidiSQL:
            return [
                home.appendingPathComponent("Library/Application Support/HeidiSQL/heidisql.ini"),
                home.appendingPathComponent(".heidisql/heidisql.ini")
            ]
        case .sequelAce:
            return [
                home.appendingPathComponent("Library/Containers/com.sequel-ace.sequel-ace/Data/Library/Application Support/Sequel Ace/Data/Favorites.plist"),
                home.appendingPathComponent("Library/Application Support/Sequel Ace/Data/Favorites.plist")
            ]
        case .sequelPro:
            return [
                home.appendingPathComponent("Library/Application Support/Sequel Pro/Data/Favorites.plist")
            ]
        }
    }
}
