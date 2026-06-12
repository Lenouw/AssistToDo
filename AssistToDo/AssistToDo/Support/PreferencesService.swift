//
//  PreferencesService.swift
//  AssistToDo
//
//  Export / import de toutes les préférences dans un fichier JSON portable
//  (pour migrer vers un autre Mac sans tout reconfigurer).
//

import AppKit

struct Preferences: Codable {
    var whisperModel: String?
    var openRouterModel: String?
    var routingEnabled: Bool?
    var defaultCalendar: String?
    var defaultReminderList: String?
    var defaultNote: String?
    var calendarPerso: String?
    var calendarCommun: String?
    var calendarPro: String?
    var hotkey: String?       // valeur brute KeyboardShortcuts_capture
    var apiKey: String?       // clé OpenRouter (Keychain)
}

enum PreferencesService {
    private static let d = UserDefaults.standard
    private static let hotkeyKey = "KeyboardShortcuts_capture"

    static func current() -> Preferences {
        Preferences(
            whisperModel: d.string(forKey: "whisperModel"),
            openRouterModel: d.string(forKey: "openRouterModel"),
            routingEnabled: d.object(forKey: "routingEnabled") as? Bool,
            defaultCalendar: d.string(forKey: "defaultCalendar"),
            defaultReminderList: d.string(forKey: "defaultReminderList"),
            defaultNote: d.string(forKey: "defaultNote"),
            calendarPerso: d.string(forKey: "calendar_perso"),
            calendarCommun: d.string(forKey: "calendar_commun"),
            calendarPro: d.string(forKey: "calendar_pro"),
            hotkey: d.string(forKey: hotkeyKey),
            apiKey: KeychainStore.apiKey().isEmpty ? nil : KeychainStore.apiKey()
        )
    }

    static func apply(_ p: Preferences) {
        if let v = p.whisperModel { d.set(v, forKey: "whisperModel") }
        if let v = p.openRouterModel { d.set(v, forKey: "openRouterModel") }
        if let v = p.routingEnabled { d.set(v, forKey: "routingEnabled") }
        if let v = p.defaultCalendar { d.set(v, forKey: "defaultCalendar") }
        if let v = p.defaultReminderList { d.set(v, forKey: "defaultReminderList") }
        if let v = p.defaultNote { d.set(v, forKey: "defaultNote") }
        if let v = p.calendarPerso { d.set(v, forKey: "calendar_perso") }
        if let v = p.calendarCommun { d.set(v, forKey: "calendar_commun") }
        if let v = p.calendarPro { d.set(v, forKey: "calendar_pro") }
        if let v = p.hotkey { d.set(v, forKey: hotkeyKey) }
        if let v = p.apiKey, !v.isEmpty { KeychainStore.setAPIKey(v) }
    }

    // MARK: - Fichier

    @MainActor
    static func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "AssistToDo-preferences.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(current())
            try data.write(to: url)
        } catch {
            print("Export préférences échoué : \(error)")
        }
    }

    @MainActor
    @discardableResult
    static func importFromFile() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let data = try Data(contentsOf: url)
            let prefs = try JSONDecoder().decode(Preferences.self, from: data)
            apply(prefs)
            return true
        } catch {
            print("Import préférences échoué : \(error)")
            return false
        }
    }
}
