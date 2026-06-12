//
//  KeychainStore.swift
//  AssistToDo
//
//  Stockage des secrets en Keychain (jamais en clair dans UserDefaults) :
//  clé API OpenRouter + token de synchronisation Toudou.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.assisttodo.openrouter"
    private static let apiKeyAccount = "api-key"
    private static let toudouTokenAccount = "toudou-token"

    // MARK: - Générique

    private static func set(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        // Lisible après le premier déverrouillage de session (app au démarrage, avant interaction).
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func get(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    // MARK: - OpenRouter

    static func setAPIKey(_ value: String) { set(value, account: apiKeyAccount) }
    static func apiKey() -> String { get(account: apiKeyAccount) }
    static var hasAPIKey: Bool { !apiKey().isEmpty }

    // MARK: - Token de synchronisation Toudou

    static func setToudouToken(_ value: String) { set(value, account: toudouTokenAccount) }
    static func toudouToken() -> String { get(account: toudouTokenAccount) }
    static var hasToudouToken: Bool { !toudouToken().isEmpty }
}
