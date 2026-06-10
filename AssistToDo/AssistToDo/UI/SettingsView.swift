//
//  SettingsView.swift
//  AssistToDo
//
//  Fenêtre Réglages : raccourci, modèle de transcription, clé OpenRouter,
//  ouverture au démarrage, permissions micro et notifications.
//

import SwiftUI
import AVFoundation
import ServiceManagement
import UserNotifications
import KeyboardShortcuts

struct SettingsView: View {
    @AppStorage("whisperModel") private var whisperModel: String = "base"
    @State private var apiKey: String = ""
    @State private var apiKeySaved: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var notifAuthorized: Bool = false

    private let models = ["tiny", "base", "small"]

    var body: some View {
        Form {
            Section("Raccourci de capture") {
                KeyboardShortcuts.Recorder("Maintenir pour parler :", name: .capture)
                Text("Maintiens ce raccourci, parle, relâche. Défaut : ⌃⌥Espace.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Transcription") {
                Picker("Modèle Whisper", selection: $whisperModel) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                Text("base = bon compromis vitesse/qualité sur un MacBook Air.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("OpenRouter (parsing des tâches)") {
                SecureField("Clé API (sk-or-...)", text: $apiKey)
                HStack {
                    Button("Enregistrer la clé") {
                        KeychainStore.setAPIKey(apiKey)
                        apiKeySaved = KeychainStore.hasAPIKey
                    }
                    if apiKeySaved {
                        Label("Clé enregistrée", systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
            }

            Section("Démarrage") {
                Toggle("Ouvrir AssistToDo au démarrage", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
            }

            Section("Permissions") {
                permissionRow(
                    title: "Microphone",
                    granted: micStatus == .authorized,
                    action: requestMic
                )
                permissionRow(
                    title: "Notifications",
                    granted: notifAuthorized,
                    action: requestNotifications
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .onAppear(perform: refresh)
    }

    @ViewBuilder
    private func permissionRow(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Autorisé", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Autoriser", action: action)
            }
        }
    }

    // MARK: - Actions

    private func refresh() {
        apiKeySaved = KeychainStore.hasAPIKey
        if apiKey.isEmpty { apiKey = KeychainStore.apiKey() }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        UNUserNotificationCenter.current().getNotificationSettings { s in
            Task { @MainActor in self.notifAuthorized = (s.authorizationStatus == .authorized) }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            print("Login item error: \(error)")
        }
    }

    private func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in self.micStatus = AVCaptureDevice.authorizationStatus(for: .audio) }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.notifAuthorized = granted }
        }
    }
}
