//
//  AppModel.swift
//  AssistToDoiOS
//
//  Câble la couche partagée AssistToDoKit pour l'app iPhone : store SwiftData, notifications,
//  transcription, synchro Toudou, pipeline de capture. Source unique injectée dans la vue.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import UserNotifications
import AssistToDoCore
import AssistToDoKit

@MainActor
final class AppModel: ObservableObject {
    let store: TaskStore
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

    // Slug WhisperKit (même liste que macOS, vérifiée sur argmaxinc/whisperkit-coreml).
    // Défaut iPhone : "small" (FR correct, ~480 Mo) ; les modèles large restent dispo en option.
    static let defaultWhisperModel = "small"
    static let defaultOpenRouterModel = "google/gemini-2.5-flash"

    init() {
        #if DEBUG
        Self.seedDevSecretsIfNeeded()   // confort de dév : injecte les secrets s'ils manquent
        #endif
        let store = TaskStore()
        let notifications = NotificationManager(store: store)
        let whisper = UserDefaults.standard.string(forKey: "whisperModel") ?? Self.defaultWhisperModel
        let transcriber = Transcriber(model: whisper)
        let orModel = UserDefaults.standard.string(forKey: "openRouterModel") ?? Self.defaultOpenRouterModel
        let parser = TaskParser(client: OpenRouterClient(model: orModel))

        self.store = store
        self.notifications = notifications
        self.transcriber = transcriber
        self.capture = CaptureController(transcriber: transcriber, parser: parser,
                                         store: store, notifications: notifications)
        self.sync = SyncCoordinator(store: store)

        store.onScheduleReminder = { [weak notifications] rec in notifications?.schedule(for: rec) }
        store.onCancelNotification = { [weak notifications] id in notifications?.cancel(id: id) }
        notifications.onOpenList = { [weak self] in self?.showCapture = false }
        EventKitService.shared.refreshCachedNames()

        // Reflète l'état de chargement du modèle Whisper dans l'UI (bandeau d'attente au 1er run).
        transcriber.$isReady.assign(to: &$transcriberReady)
    }

    // MARK: - Cycle de vie

    /// À l'ouverture / au retour au premier plan : synchro Toudou + agenda du jour + capture en attente.
    func onForeground() {
        sync.start()
        Task { await store.refreshToday() }
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
