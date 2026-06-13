//
//  SettingsView.swift
//  AssistToDoiOS
//
//  Réglages : connexion Toudou (URL + token), clé OpenRouter, modèle Whisper, permissions.
//  Secrets en Keychain (jamais en clair). Le modèle Whisper est pris en compte au redémarrage.
//

import SwiftUI
import AssistToDoKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage("toudouBaseURL") private var toudouURL = ""
    @AppStorage("whisperModel") private var whisperModel = AppModel.defaultWhisperModel
    @AppStorage("openRouterModel") private var openRouterModel = AppModel.defaultOpenRouterModel
    @AppStorage("routingEnabled") private var routingEnabled = true

    @State private var toudouToken = ""
    @State private var apiKey = ""
    @State private var savedFlash = false

    // Slugs WhisperKit vérifiés (repo argmaxinc/whisperkit-coreml), mêmes que macOS.
    private let whisperModels: [(slug: String, label: String)] = [
        ("tiny", "Tiny · ultra rapide, basique"),
        ("base", "Base · rapide"),
        ("small", "Small · équilibré (défaut iPhone)"),
        ("distil-whisper_distil-large-v3_turbo", "Distil Large v3 Turbo · précis, assez rapide"),
        ("openai_whisper-large-v3_turbo", "Large v3 Turbo · très précis, plus lent"),
        ("openai_whisper-large-v3", "Large v3 · précision max, le plus lent")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Connexion Toudou") {
                    TextField("URL (défaut : prod)", text: $toudouURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Token", text: $toudouToken)
                    Button("Enregistrer la connexion") { saveToudou() }
                    Button("Synchroniser maintenant") { SyncCoordinator.shared?.syncNow() }
                }

                Section("OpenRouter (structuration)") {
                    SecureField("Clé API", text: $apiKey)
                    TextField("Modèle", text: $openRouterModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Enregistrer la clé") { saveKey() }
                }

                Section("Transcription") {
                    Picker("Modèle Whisper", selection: $whisperModel) {
                        ForEach(whisperModels, id: \.slug) { Text($0.label).tag($0.slug) }
                    }
                    Text("Changement pris en compte au prochain lancement.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Routage") {
                    Toggle("Routage intelligent (Rappels / Calendrier)", isOn: $routingEnabled)
                }

                Section("Permissions") {
                    Button("Autoriser le micro") { Task { _ = await model.requestMicrophone() } }
                    Button("Autoriser Rappels + Calendrier") { Task { await model.requestRemindersAndCalendar() } }
                    Button("Autoriser les notifications") { Task { await model.requestNotifications() } }
                }

                Section {
                    HStack {
                        Text("Version"); Spacer()
                        Text(BuildInfo.date).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Réglages")
            .onAppear {
                toudouToken = KeychainStore.toudouToken()
                apiKey = KeychainStore.apiKey()
            }
            .alert("Enregistré", isPresented: $savedFlash) { Button("OK", role: .cancel) {} }
        }
    }

    private func saveToudou() {
        KeychainStore.setToudouToken(toudouToken)
        SyncCoordinator.shared?.start()
        savedFlash = true
    }

    private func saveKey() {
        KeychainStore.setAPIKey(apiKey)
        savedFlash = true
    }
}
