//
//  AppDelegate.swift
//  AssistToDo
//

import AppKit
import Combine
import AssistToDoKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()
    private var reminderRefreshTimer: Timer?
    private var store: TaskStore!
    private var menuBar: MenuBarController!
    private var listController: ListWindowController!
    private var hotkey: HotkeyManager!
    private var transcriber: Transcriber!
    private var notifications: NotificationManager!
    private var capture: CaptureCoordinator!
    private var captureStore: CaptureStore!
    private var onboarding: OnboardingController!
    private var sync: SyncCoordinator!
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

        menuBar = MenuBarController(
            store: store,
            onOpenList: { [weak self] in self?.listController.show() },
            onOpenSettings: { [weak self] in self?.listController.showSettings() },
            onOpenCaptures: { [weak self] in self?.listController.showCaptures() }
        )

        // Raccourci global push-to-talk : maintien = capture + HUD, relâche = stop + transcription + parsing.
        // Défaut aligné sur SettingsView : large-v3-turbo (le distil perdait les dates FR).
        let whisper = UserDefaults.standard.string(forKey: "whisperModel") ?? "openai_whisper-large-v3_turbo"
        let llmModel = UserDefaults.standard.string(forKey: "openRouterModel") ?? "google/gemini-2.5-flash"
        transcriber = Transcriber(model: whisper)   // pré-charge le modèle au lancement
        notifications = NotificationManager(store: store)
        notifications.onOpenList = { [weak self] in self?.listController.show() }
        // Le store annule/replanifie les notifs lors des suppressions et reports (swipe).
        store.onCancelNotification = { [weak self] id in self?.notifications.cancel(id: id) }
        store.onScheduleReminder = { [weak self] record in self?.notifications.schedule(for: record) }
        let parser = TaskParser(client: OpenRouterClient(model: llmModel))
        // Journal des captures (filet de sécurité). Repli in-memory si le store persistant échoue (jamais crash).
        let captureStore: CaptureStore = (try? CaptureStore()) ?? (try! CaptureStore(inMemory: true))
        self.captureStore = captureStore
        let macRouter = MacTaskRouter(store: store, notifications: notifications)
        let processor = CaptureProcessor(store: captureStore,
                                         transcriber: TranscriberAdapter(transcriber: transcriber),
                                         parser: parser, router: macRouter)
        capture = CaptureCoordinator(
            transcriber: transcriber, parser: parser,
            captureStore: captureStore, macRouter: macRouter, processor: processor
        )
        // Panneau de droite (liste + Réglages + Captures, accessibles depuis son en-tête).
        listController = ListWindowController(store: store, captureStore: captureStore, processor: processor, transcriber: transcriber)
        // Rétention : purge les audios des captures faites > N jours (défaut 30 ; 0 = indéfini).
        captureStore.purgeAudio(olderThanDays: UserDefaults.standard.object(forKey: "captureRetentionDays") as? Int ?? 30)
        // Rejoue les captures en attente DÈS que le modèle Whisper est prêt. Au lancement le modèle
        // charge en async : lancer reprocess tout de suite échouerait ("transcription indisponible")
        // et la capture resterait bloquée. $isReady émet sa valeur courante à l'abonnement, donc ça
        // couvre aussi le cas "déjà prêt".
        transcriber.$isReady
            .filter { $0 }
            .sink { [weak self] _ in self?.capture.reprocessPending() }
            .store(in: &cancellables)
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

        // Synchronisation Toudou (no-op tant que URL + token ne sont pas configurés dans les Réglages).
        sync = SyncCoordinator(store: store)
        sync.start()

        // Vérifie discrètement s'il existe une version plus récente sur GitHub (silencieux si à jour).
        UpdateChecker.check()

        // Rappels iCloud : couche in-app de « nag ». À chaque changement de la liste des rappels
        // ouverts, on (re)programme les 2 notifs/jour pour ceux en retard. Refresh initial + périodique
        // (toutes les 10 min) pour que l'état « en retard » et les nags restent à jour dans la journée.
        store.$openReminders
            .dropFirst()
            .sink { [weak self] _ in self?.notifications.rescheduleReminderNags() }
            .store(in: &cancellables)
        Task { [weak self] in await self?.store.refreshToday(); self?.notifications.rescheduleReminderNags() }
        reminderRefreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.store.refreshToday()
                self?.store.reload()   // bascule les tâches faites > 24h vers l'Archive
            }
        }
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
