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

        // Raccourci global. Capture vocale câblée à la prochaine étape ;
        // pour l'instant, relâcher ouvre la liste (preuve que le raccourci fonctionne).
        hotkey = HotkeyManager()
        hotkey.onPressStart = { print("Raccourci maintenu (début capture)") }
        hotkey.onPressEnd = { [weak self] in
            print("Raccourci relâché (fin capture)")
            self?.listController.show()
        }
    }
}
