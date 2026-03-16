//
//  ConnectionPasswordKeychain.swift
//  sqlmanager
//

import Foundation
import Security

enum PasswordKeychain {
    private static let service = "SqlManager.profiles"

    @discardableResult
    static func save(password: String, forProfileID profileID: UUID) -> Bool {
        guard let passwordData = password.data(using: .utf8) else { return false }

        let account = profileID.uuidString
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = passwordData

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
}
