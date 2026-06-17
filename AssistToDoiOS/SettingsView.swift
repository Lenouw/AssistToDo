//
//  SettingsView.swift
//  AssistToDoiOS
//
//  Réglages : connexion Toudou (URL + token), clé OpenRouter, modèle Whisper, permissions.
//  Secrets en Keychain (jamais en clair). Le modèle Whisper est pris en compte au redémarrage.
//

import SwiftUI
import UIKit
import AssistToDoCore
import AssistToDoKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("toudouBaseURL") private var toudouURL = ""
    @AppStorage("whisperModel") private var whisperModel = AppModel.defaultWhisperModel
    @AppStorage("openRouterModel") private var openRouterModel = AppModel.defaultOpenRouterModel
    @AppStorage("routingEnabled") private var routingEnabled = true
    @AppStorage("iosLayout") private var iosLayout: AppLayout = .segmented

    @State private var toudouToken = ""
    @State private var apiKey = ""
    @State private var savedFlash = false
    @State private var copiedFlash = false

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

                Section("Affichage") {
                    Picker("Disposition de l'écran", selection: $iosLayout) {
                        Text("Segmentée (onglets en haut)").tag(AppLayout.segmented)
                        Text("Empilée (tout en scroll)").tag(AppLayout.stacked)
                    }
                    Text("Segmentée : une zone à la fois (À faire · Rappels · Agenda · Fait). Empilée : zones en scroll, historique via l'horloge.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Permissions") {
                    Button("Autoriser le micro") { Task { _ = await model.requestMicrophone() } }
                    Button("Autoriser Rappels + Calendrier") { Task { await model.requestRemindersAndCalendar() } }
                    Button("Autoriser les notifications") { Task { await model.requestNotifications() } }
                }

                shoppingSection

                Section {
                    HStack {
                        Text("Version"); Spacer()
                        Text(BuildInfo.date).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
            .onAppear {
                toudouToken = KeychainStore.toudouToken()
                apiKey = KeychainStore.apiKey()
            }
            .alert("Enregistré", isPresented: $savedFlash) { Button("OK", role: .cancel) {} }
            .alert("Liste copiée", isPresented: $copiedFlash) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Colle-la dans tes Notes Apple (tu ajoutes les cases à cocher).")
            }
        }
    }

    // MARK: - Liste de courses
    //
    // L'app ne peut pas écrire de cases cochables dans Apple Notes sur iOS. Les articles dictés
    // par la voix s'accumulent ici ; tu les copies et tu les colles toi-même dans ta note partagée.

    private var shoppingSection: some View {
        Section("Liste de courses") {
            if store.shoppingItems.isEmpty {
                Text("Vide. Dicte des articles, ils s'ajoutent ici.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(store.shoppingItems) { Text($0.text) }
            }
            Button {
                UIPasteboard.general.string = store.shoppingItems.map { $0.text }.joined(separator: "\n")
                copiedFlash = true
            } label: {
                Label("Copier la liste", systemImage: "doc.on.doc")
            }
            .disabled(store.shoppingItems.isEmpty)

            if !store.shoppingItems.isEmpty {
                Button(role: .destructive) {
                    for id in store.shoppingItems.map(\.id) { store.delete(id: id) }
                } label: {
                    Label("Vider la liste", systemImage: "trash")
                }
            }
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
