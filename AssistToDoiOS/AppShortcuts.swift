//
//  AppShortcuts.swift
//  AssistToDoiOS
//
//  Expose RecordVoiceIntent à Siri, à l'app Raccourcis et au mappage du bouton Action.
//  La phrase DOIT contenir le nom de l'app (\(.applicationName)) — contrainte Apple.
//

import AppIntents

struct AssistToDoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordVoiceIntent(),
            phrases: [
                "Nouvelle note dans \(.applicationName)",
                "Capture une note dans \(.applicationName)",
                "Note vocale \(.applicationName)"
            ],
            shortTitle: "Note vocale",
            systemImageName: "mic.fill"
        )
    }
}
