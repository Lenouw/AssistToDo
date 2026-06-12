//
//  SettingsView.swift
//  AssistToDo
//
//  Réglages : raccourci, transcription, intelligence (OpenRouter), destinations
//  (routage Rappels/Calendrier + défauts), démarrage, permissions.
//

import SwiftUI
import AVFoundation
import ServiceManagement
import UserNotifications
import KeyboardShortcuts

struct SettingsView: View {
    @AppStorage("whisperModel") private var whisperModel: String = "base"
    @AppStorage("routingEnabled") private var routingEnabled: Bool = true
    @AppStorage("defaultCalendar") private var defaultCalendar: String = ""
    @AppStorage("defaultReminderList") private var defaultReminderList: String = ""
    @AppStorage("defaultNote") private var defaultNote: String = "Courses"
    @AppStorage("calendar_perso") private var calendarPerso: String = ""
    @AppStorage("calendar_commun") private var calendarCommun: String = ""
    @AppStorage("calendar_pro") private var calendarPro: String = ""

    @State private var apiKey: String = ""
    @State private var apiKeySaved: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var notifAuthorized: Bool = false

    @State private var calendarAccess = false
    @State private var remindersAccess = false
    @State private var calendars: [String] = []
    @State private var reminderLists: [String] = []

    private let models = ["tiny", "base", "small"]

    var body: some View {
        Form {
            Section("Raccourci de capture") {
                KeyboardShortcuts.Recorder("Maintenir pour parler :", name: .capture)
                Text("Appui long = capture vocale. Appui bref = ouvre la liste.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Transcription") {
                Picker("Modèle Whisper", selection: $whisperModel) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                Text("base = bon compromis vitesse/qualité. Changement pris en compte au redémarrage.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Intelligence (OpenRouter)") {
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

            Section("Destinations") {
                Toggle("Router vers Rappels et Calendrier Apple", isOn: $routingEnabled)
                Text("Le LLM range chaque capture : événement → Calendrier, vrai rappel → Rappels, note rapide → liste locale. Désactivé, tout reste en local.")
                    .font(.caption).foregroundStyle(.secondary)

                if routingEnabled {
                    // Calendrier
                    permissionRow("Accès Calendrier", granted: calendarAccess) { requestCalendar() }
                    if calendarAccess && !calendars.isEmpty {
                        Picker("Agenda perso", selection: $calendarPerso) { calendarOptions() }
                        Picker("Agenda commun", selection: $calendarCommun) { calendarOptions() }
                        Picker("Agenda pro", selection: $calendarPro) { calendarOptions() }
                        Picker("Agenda par défaut", selection: $defaultCalendar) { calendarOptions() }
                        Text("Le LLM classe chaque rdv (perso / commun / pro) et l'ajoute à l'agenda choisi ici.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    // Rappels
                    permissionRow("Accès Rappels", granted: remindersAccess) { requestReminders() }
                    if remindersAccess && !reminderLists.isEmpty {
                        Picker("Liste Rappels par défaut", selection: $defaultReminderList) {
                            Text("Liste système").tag("")
                            ForEach(reminderLists, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    // Notes (liste de courses)
                    TextField("Note de courses par défaut", text: $defaultNote)
                    Text("Les articles de courses dictés sont ajoutés à cette note Apple (créée si absente). Dicte « ajoute du lait » ou « sur la liste de courses ».")
                        .font(.caption).foregroundStyle(.secondary)

                    Text("Cible précise possible à la voix : « dans mon calendrier BoulouFlo », « dans ma liste Courses », « dans ma note Maison ».")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Démarrage") {
                Toggle("Ouvrir AssistToDo au démarrage", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
            }

            Section("Permissions système") {
                permissionRow("Microphone", granted: micStatus == .authorized) { requestMic() }
                permissionRow("Notifications", granted: notifAuthorized) { requestNotifications() }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: refresh)
    }

    @ViewBuilder
    private func calendarOptions() -> some View {
        Text("Aucun / système").tag("")
        ForEach(calendars, id: \.self) { Text($0).tag($0) }
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

    // MARK: - Actions

    private func refresh() {
        apiKeySaved = KeychainStore.hasAPIKey
        if apiKey.isEmpty { apiKey = KeychainStore.apiKey() }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        UNUserNotificationCenter.current().getNotificationSettings { s in
            Task { @MainActor in self.notifAuthorized = (s.authorizationStatus == .authorized) }
        }
        EventKitService.shared.refreshCachedNames()
        calendarAccess = EventKitService.shared.hasCalendarAccess
        remindersAccess = EventKitService.shared.hasRemindersAccess
        calendars = EventKitService.shared.calendarTitles
        reminderLists = EventKitService.shared.reminderListTitles
    }

    private func requestCalendar() {
        Task {
            _ = try? await EventKitService.shared.ensureCalendarAccess()
            await MainActor.run {
                calendarAccess = EventKitService.shared.hasCalendarAccess
                calendars = EventKitService.shared.calendarTitles
            }
        }
    }

    private func requestReminders() {
        Task {
            _ = try? await EventKitService.shared.ensureRemindersAccess()
            await MainActor.run {
                remindersAccess = EventKitService.shared.hasRemindersAccess
                reminderLists = EventKitService.shared.reminderListTitles
            }
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
