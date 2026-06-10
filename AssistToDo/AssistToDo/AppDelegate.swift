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
    private var notifications: NotificationManager!
    private var toast: ToastController!
    private var capture: CaptureCoordinator!
    private var pressStart: TimeInterval?
    private static let tapThreshold: TimeInterval = 0.25

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

        // Raccourci global push-to-talk : maintien = capture + HUD, relâche = stop + transcription + parsing.
        let whisper = UserDefaults.standard.string(forKey: "whisperModel") ?? "base"
        let llmModel = UserDefaults.standard.string(forKey: "openRouterModel") ?? "google/gemini-2.5-flash"
        transcriber = Transcriber(model: whisper)   // pré-charge le modèle au lancement
        notifications = NotificationManager()
        toast = ToastController()
        let parser = TaskParser(client: OpenRouterClient(model: llmModel))
        capture = CaptureCoordinator(
            transcriber: transcriber, parser: parser, store: store,
            notifications: notifications, toast: toast
        )
        hotkey = HotkeyManager()
        hotkey.onPressStart = { [weak self] in
            self?.pressStart = ProcessInfo.processInfo.systemUptime
            self?.capture.begin()
        }
        hotkey.onPressEnd = { [weak self] in
            guard let self else { return }
            let held = self.pressStart.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
            self.pressStart = nil
            if held < Self.tapThreshold {
                self.capture.cancel()        // appui bref → ouvre la liste
                self.listController.show()
            } else {
                self.capture.end()           // appui long → transcription
            }
        }
    }
}
