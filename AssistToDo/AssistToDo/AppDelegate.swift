//
//  AppDelegate.swift
//  AssistToDo
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: TaskStore!
    private var menuBar: MenuBarController!
    private var listController: ListWindowController!
    private var settingsController: SettingsWindowController!
    private var hotkey: HotkeyManager!
    private var transcriber: Transcriber!
    private var capture: CaptureCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App accessoire : pas d'icône Dock, vit dans la barre de menus.
        NSApp.setActivationPolicy(.accessory)

        store = TaskStore()                       // ouvre SwiftData + applique le rollover au lancement
        settingsController = SettingsWindowController()
        listController = ListWindowController(store: store) { [weak self] in
            self?.settingsController.show()
        }

        menuBar = MenuBarController(
            store: store,
            onOpenList: { [weak self] in self?.listController.show() },
            onOpenSettings: { [weak self] in self?.settingsController.show() }
        )

        // Raccourci global push-to-talk : maintien = capture + HUD, relâche = stop + transcription.
        let model = UserDefaults.standard.string(forKey: "whisperModel") ?? "base"
        transcriber = Transcriber(model: model)   // pré-charge le modèle au lancement
        capture = CaptureCoordinator(transcriber: transcriber)
        hotkey = HotkeyManager()
        hotkey.onPressStart = { [weak self] in self?.capture.begin() }
        hotkey.onPressEnd = { [weak self] in self?.capture.end() }
    }
}
