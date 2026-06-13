//
//  PreferencesService.swift
//  AssistToDoKit
//
//  Export / import de toutes les préférences dans un fichier JSON portable
//  (pour migrer vers un autre Mac sans tout reconfigurer).
//
//  L'export/import par panneau de fichier est macOS-only (NSSavePanel/NSOpenPanel) ;
//  la lecture/écriture des préférences (current/apply) est multiplateforme.
//

import Foundation
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

public struct Preferences: Codable {
    public var whisperModel: String?
    public var openRouterModel: String?
    public var routingEnabled: Bool?
    public var defaultCalendar: String?
    public var defaultReminderList: String?
    public var defaultNote: String?
    public var eventAlarmsEnabled: Bool?
    public var customRoutingRules: String?
    public var calendarPerso: String?
    public var calendarCommun: String?
    public var calendarPro: String?
    public var calendarStudio: String?
    public var studioBlockStart: Int?
    public var studioBlockEnd: Int?
    public var hotkey: String?       // valeur brute KeyboardShortcuts_capture
    public var apiKey: String?       // clé OpenRouter (Keychain)
}

public enum PreferencesService {
    private static let d = UserDefaults.standard
    private static let hotkeyKey = "KeyboardShortcuts_capture"

    public static func current() -> Preferences {
        Preferences(
            whisperModel: d.string(forKey: "whisperModel"),
            openRouterModel: d.string(forKey: "openRouterModel"),
            routingEnabled: d.object(forKey: "routingEnabled") as? Bool,
            defaultCalendar: d.string(forKey: "defaultCalendar"),
            defaultReminderList: d.string(forKey: "defaultReminderList"),
            defaultNote: d.string(forKey: "defaultNote"),
            eventAlarmsEnabled: d.object(forKey: "eventAlarmsEnabled") as? Bool,
            customRoutingRules: d.string(forKey: "customRoutingRules"),
            calendarPerso: d.string(forKey: "calendar_perso"),
            calendarCommun: d.string(forKey: "calendar_commun"),
            calendarPro: d.string(forKey: "calendar_pro"),
            calendarStudio: d.string(forKey: "calendar_studio"),
            studioBlockStart: d.object(forKey: "studioBlockStart") as? Int,
            studioBlockEnd: d.object(forKey: "studioBlockEnd") as? Int,
            hotkey: d.string(forKey: hotkeyKey),
            apiKey: KeychainStore.apiKey().isEmpty ? nil : KeychainStore.apiKey()
        )
    }

    public static func apply(_ p: Preferences) {
        if let v = p.whisperModel { d.set(v, forKey: "whisperModel") }
        if let v = p.openRouterModel { d.set(v, forKey: "openRouterModel") }
        if let v = p.routingEnabled { d.set(v, forKey: "routingEnabled") }
        if let v = p.defaultCalendar { d.set(v, forKey: "defaultCalendar") }
        if let v = p.defaultReminderList { d.set(v, forKey: "defaultReminderList") }
        if let v = p.defaultNote { d.set(v, forKey: "defaultNote") }
        if let v = p.eventAlarmsEnabled { d.set(v, forKey: "eventAlarmsEnabled") }
        if let v = p.customRoutingRules { d.set(v, forKey: "customRoutingRules") }
        if let v = p.calendarPerso { d.set(v, forKey: "calendar_perso") }
        if let v = p.calendarCommun { d.set(v, forKey: "calendar_commun") }
        if let v = p.calendarPro { d.set(v, forKey: "calendar_pro") }
        if let v = p.calendarStudio { d.set(v, forKey: "calendar_studio") }
        if let v = p.studioBlockStart { d.set(v, forKey: "studioBlockStart") }
        if let v = p.studioBlockEnd { d.set(v, forKey: "studioBlockEnd") }
        if let v = p.hotkey { d.set(v, forKey: hotkeyKey) }
        if let v = p.apiKey, !v.isEmpty { KeychainStore.setAPIKey(v) }
    }

    // MARK: - Fichier (macOS uniquement)

    #if canImport(AppKit)
    @MainActor
    public static func export() {
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
    public static func importFromFile() -> Bool {
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
    #endif
}
