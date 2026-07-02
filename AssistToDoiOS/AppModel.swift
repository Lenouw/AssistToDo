//
//  AppModel.swift
//  AssistToDoiOS
//
//  Câble la couche partagée AssistToDoKit pour l'app iPhone : store SwiftData, notifications,
//  transcription, synchro Toudou, pipeline de capture. Source unique injectée dans la vue.
//

import Foundation
import os
import SwiftUI
import Combine
import AVFoundation
import UserNotifications
import AssistToDoCore
import AssistToDoKit

@MainActor
final class AppModel: ObservableObject {
    let store: TaskStore
    let captureStore: CaptureStore          // journal des captures (filet de sécurité)
    let captureProcessor: CaptureProcessor  // pipeline rejouable (écran Captures + relance auto)
    let notifications: NotificationManager
    let transcriber: Transcriber
    let sync: SyncCoordinator
    let capture: CaptureController

    /// Présente l'écran de capture (déclenché par le bouton in-app ou un App Intent).
    @Published var showCapture = false
    /// La capture doit démarrer automatiquement (déclenchée par Action Button / Siri / widget).
    @Published var autoStartCapture = false
    /// Modèle de transcription chargé (faux pendant le téléchargement du 1er lancement).
    /// Reflète `Transcriber.isReady` pour piloter un bandeau d'attente dans l'UI.
    @Published var transcriberReady = false
    /// État détaillé de préparation (téléchargement %, préparation) pour un bandeau informatif.
    @Published var transcriberReadiness: Transcriber.Readiness = .downloading(0)
    /// Incrémenté quand la visibilité des agendas change (Réglages) → la vue Agenda se rafraîchit.
    @Published var agendaVisibilityVersion = 0
    /// Toast « revenir en arrière » : confirmation visible de la dernière action + bouton Annuler.
    @Published var undoToast: UndoToast?

    struct UndoToast: Identifiable {
        let id = UUID()
        let message: String
        let undo: (() -> Void)?   // nil = confirmation simple, sans annulation possible
    }

    /// Affiche une confirmation en bas d'écran pendant ~6 s, avec « Annuler » si `undo` est fourni.
    func showToast(_ message: String, undo: (() -> Void)? = nil) {
        let toast = UndoToast(message: message, undo: undo)
        undoToast = toast
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if self?.undoToast?.id == toast.id { self?.undoToast = nil }
        }
    }

    /// Annule une capture entière : supprime ce qu'elle a créé (tâches locales, rappels et
    /// événements Apple) et marque la capture comme annulée (l'audio reste dans Captures).
    func undoCapture(outcomes: [RoutedOutcome], captureId: UUID) {
        for o in outcomes {
            if let ext = o.record.externalId {
                switch o.destination {
                case .calendar:  EventKitService.shared.deleteEvent(id: ext)
                case .reminders: EventKitService.shared.deleteReminder(id: ext)
                default: break
                }
            }
            if let sid = o.storedId { store.delete(id: sid) }
        }
        captureStore.update(id: captureId) {
            $0.producedTaskIds = []; $0.parsedSummary = "(annulée)"; $0.needsEnrichment = false
        }
        Haptics.light()
        Task { await store.refreshToday() }
    }

    // Slug WhisperKit (même liste que macOS, vérifiée sur argmaxinc/whisperkit-coreml).
    // Défaut iPhone : "small" (FR correct, ~480 Mo) ; les modèles large restent dispo en option.
    static let defaultWhisperModel = "small"
    static let defaultOpenRouterModel = "google/gemini-2.5-flash"

    /// true = le journal des captures n'a PAS pu s'ouvrir sur disque (repli mémoire volatile).
    /// Affiché en bandeau rouge : sinon les captures « disparaissent » silencieusement au relaunch.
    let captureStoreIsVolatile: Bool
    /// Erreur exacte d'ouverture du journal (diagnostic affiché dans le bandeau).
    let captureStoreError: String?

    init() {
        #if DEBUG
        Self.seedDevSecretsIfNeeded()   // confort de dév : injecte les secrets s'ils manquent
        #endif
        let store = TaskStore()
        // Journal de capture : PARTAGE le container SwiftData de TaskStore (même fichier). Ouvrir
        // une 2ᵉ connexion sur le même .store échouait par intermittence (verrou SQLite au boot)
        // → repli mémoire silencieux → captures « disparues ». Un seul container = plus de course.
        let captureStore = CaptureStore(sharing: store.container)
        captureStoreIsVolatile = false
        captureStoreError = nil
        let notifications = NotificationManager(store: store)
        let whisper = UserDefaults.standard.string(forKey: "whisperModel") ?? Self.defaultWhisperModel
        let transcriber = Transcriber(model: whisper)
        let orModel = UserDefaults.standard.string(forKey: "openRouterModel") ?? Self.defaultOpenRouterModel
        let parser = TaskParser(client: OpenRouterClient(model: orModel))
        let router = IOSTaskRouter(store: store, notifications: notifications)
        let processor = CaptureProcessor(store: captureStore,
                                         transcriber: TranscriberAdapter(transcriber: transcriber),
                                         parser: parser, router: router)

        self.store = store
        self.captureStore = captureStore
        self.captureProcessor = processor
        self.notifications = notifications
        self.transcriber = transcriber
        self.capture = CaptureController(transcriber: transcriber, parser: parser,
                                         captureStore: captureStore, router: router, processor: processor)
        self.sync = SyncCoordinator(store: store)

        store.onScheduleReminder = { [weak notifications] rec in notifications?.schedule(for: rec) }
        store.onCancelNotification = { [weak notifications] id in notifications?.cancel(id: id) }
        notifications.onOpenList = { [weak self] in self?.showCapture = false }

        // Confirmation VISIBLE de chaque capture (toast qui reste ~6 s) + « Annuler » si des
        // éléments ont été créés. La feuille peut se fermer vite : le toast, lui, reste.
        capture.onAdded = { [weak self] summaries, outcomes, capId in
            guard let self else { return }
            let message = summaries.joined(separator: "\n")
            if outcomes.isEmpty {
                self.showToast(message)   // enregistrée, traitement à venir (rien à annuler encore)
            } else {
                self.showToast(message) { [weak self] in
                    self?.undoCapture(outcomes: outcomes, captureId: capId)
                    self?.showToast("Capture annulée")
                }
            }
        }

        // Reflète l'état de chargement du modèle Whisper dans l'UI (bandeau d'attente au 1er run).
        transcriber.$isReady.assign(to: &$transcriberReady)
        transcriber.$readiness.assign(to: &$transcriberReadiness)

        // Nag des rappels en retard : re-programme les 2 notifs/jour à CHAQUE évolution des rappels
        // iCloud ouverts (cocher, reporter, sync iCloud en arrière-plan). Idempotent côté Kit.
        store.$openReminders
            .removeDuplicates()
            .sink { [weak notifications] _ in
                Task { @MainActor in notifications?.rescheduleReminderNags() }
            }
            .store(in: &cancellables)

        // Modèle de transcription prêt → rejoue les captures en attente (audio capté à froid,
        // échec de transcription…) : la promesse « aucune idée perdue » tient toute seule.
        transcriber.$isReady
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                Task { @MainActor in self?.capture.reprocessPending() }
            }
            .store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Cycle de vie

    /// À l'ouverture / au retour au premier plan : synchro Toudou + agenda du jour + capture en attente.
    func onForeground() {
        sync.start()
        capture.reprocessPending()   // rejoue les captures en échec / à enrichir (filet)
        store.reload()               // ré-applique la frontière d'archivage 24h (tâches faites → Archive)
        // Différé hors de l'init : refresh des noms calendrier/rappel (lecture EventKit) + agenda du jour.
        Task {
            EventKitService.shared.refreshCachedNames()
            await store.refreshToday()               // remplit aussi openReminders (rappels ouverts)
            notifications.rescheduleReminderNags()   // relance des rappels en retard (2 notifs/jour)
        }
        if PendingCapture.consume() {
            autoStartCapture = true
            showCapture = true
        }
    }

    func onBackground() {
        sync.stop()
    }

    // MARK: - Permissions

    func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    func requestRemindersAndCalendar() async {
        _ = try? await EventKitService.shared.ensureRemindersAccess()
        _ = try? await EventKitService.shared.ensureCalendarAccess()
        EventKitService.shared.refreshCachedNames()
    }

    // MARK: - Secrets de dév (DEBUG)

    #if DEBUG
    /// Injecte les secrets de DevSecrets dans le Keychain/UserDefaults s'ils sont absents.
    /// N'écrase jamais une valeur déjà saisie dans l'app.
    private static func seedDevSecretsIfNeeded() {
        if !DevSecrets.toudouURL.isEmpty,
           (UserDefaults.standard.string(forKey: "toudouBaseURL") ?? "").isEmpty {
            UserDefaults.standard.set(DevSecrets.toudouURL, forKey: "toudouBaseURL")
        }
        if !DevSecrets.toudouToken.isEmpty, !KeychainStore.hasToudouToken {
            KeychainStore.setToudouToken(DevSecrets.toudouToken)
        }
        if !DevSecrets.openRouterKey.isEmpty, !KeychainStore.hasAPIKey {
            KeychainStore.setAPIKey(DevSecrets.openRouterKey)
        }
    }
    #endif
}
