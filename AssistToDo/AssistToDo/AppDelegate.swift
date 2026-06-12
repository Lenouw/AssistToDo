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
    private var hotkey: HotkeyManager!
    private var transcriber: Transcriber!
    private var notifications: NotificationManager!
    private var capture: CaptureCoordinator!
    private var onboarding: OnboardingController!
    private var pressStart: TimeInterval?
    private static let tapThreshold: TimeInterval = 0.5

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Mono-instance : tue toute autre copie d'AssistToDo AVANT d'enregistrer le raccourci global.
        // Évite qu'une vieille instance (build précédente, login item) garde un raccourci fantôme
        // et interfère avec d'autres apps (ex: Wispr Flow).
        terminateOtherInstances()

        // App accessoire : pas d'icône Dock, vit dans la barre de menus.
        NSApp.setActivationPolicy(.accessory)

        store = TaskStore()                       // ouvre SwiftData + applique le rollover au lancement
        EventKitService.shared.refreshCachedNames()   // pré-charge les noms de calendriers/listes si déjà autorisé
        listController = ListWindowController(store: store)

        menuBar = MenuBarController(
            store: store,
            onOpenList: { [weak self] in self?.listController.show() },
            onOpenSettings: { [weak self] in self?.listController.showSettings() }
        )

        // Raccourci global push-to-talk : maintien = capture + HUD, relâche = stop + transcription + parsing.
        let whisper = UserDefaults.standard.string(forKey: "whisperModel") ?? "base"
        let llmModel = UserDefaults.standard.string(forKey: "openRouterModel") ?? "google/gemini-2.5-flash"
        transcriber = Transcriber(model: whisper)   // pré-charge le modèle au lancement
        notifications = NotificationManager(store: store)
        notifications.onOpenList = { [weak self] in self?.listController.show() }
        // Le store annule/replanifie les notifs lors des suppressions et reports (swipe).
        store.onCancelNotification = { [weak self] id in self?.notifications.cancel(id: id) }
        store.onScheduleReminder = { [weak self] record in self?.notifications.schedule(for: record) }
        let parser = TaskParser(client: OpenRouterClient(model: llmModel))
        capture = CaptureCoordinator(
            transcriber: transcriber, parser: parser, store: store,
            notifications: notifications
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

        // Onboarding au tout premier lancement.
        onboarding = OnboardingController()
        if onboarding.shouldShow { onboarding.show() }

        // Vérifie discrètement s'il existe une version plus récente sur GitHub (silencieux si à jour).
        UpdateChecker.check()
    }

    /// Force la fermeture de toute autre instance d'AssistToDo (même bundle id), puis attend
    /// qu'elles aient libéré leur raccourci global.
    private func terminateOtherInstances() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return }
        for app in others { app.forceTerminate() }
        // Laisse le temps à la libération du Carbon hotkey (sinon notre enregistrement échoue).
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline,
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).contains(where: { $0.processIdentifier != me }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
