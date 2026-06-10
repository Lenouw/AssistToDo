//
//  OnboardingView.swift
//  AssistToDo
//
//  Premier lancement : raccourci, permissions micro/notif, clé OpenRouter.
//

import SwiftUI
import AVFoundation
import UserNotifications
import KeyboardShortcuts

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var apiKey: String = ""
    @State private var micGranted = false
    @State private var notifGranted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bienvenue dans AssistToDo")
                    .font(.title2.bold())
                Text("Capture tes tâches à la voix, sans quitter ce que tu fais.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("1 · Le raccourci") {
                VStack(alignment: .leading, spacing: 6) {
                    KeyboardShortcuts.Recorder("Maintiens pour parler :", name: .capture)
                    Text("Appui long = capture vocale. Appui bref = ouvre ta liste.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
            }

            GroupBox("2 · Permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    permissionRow("Microphone", granted: micGranted) {
                        AVCaptureDevice.requestAccess(for: .audio) { ok in
                            Task { @MainActor in micGranted = ok }
                        }
                    }
                    permissionRow("Notifications", granted: notifGranted) {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
                            Task { @MainActor in notifGranted = ok }
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("3 · Clé OpenRouter (parsing des tâches)") {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField("Clé API (sk-or-...)", text: $apiKey)
                    Text("Sert à transformer ta phrase en tâche structurée (date, priorité…).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
            }

            HStack {
                Spacer()
                Button("Commencer") {
                    if !apiKey.isEmpty { KeychainStore.setAPIKey(apiKey) }
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            apiKey = KeychainStore.apiKey()
            UNUserNotificationCenter.current().getNotificationSettings { s in
                Task { @MainActor in notifGranted = (s.authorizationStatus == .authorized) }
            }
        }
    }

    @ViewBuilder
    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
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
}
