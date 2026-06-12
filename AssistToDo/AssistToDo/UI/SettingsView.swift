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
    @AppStorage("defaultNote") private var defaultNote: String = "LISTE Courses MAISON 2026"
    @AppStorage("eventAlarmsEnabled") private var eventAlarmsEnabled: Bool = true
    @AppStorage("customRoutingRules") private var customRoutingRules: String = ""
    @AppStorage("calendar_perso") private var calendarPerso: String = ""
    @AppStorage("calendar_commun") private var calendarCommun: String = ""
    @AppStorage("calendar_pro") private var calendarPro: String = ""
    @AppStorage("calendar_studio") private var calendarStudio: String = ""
    @AppStorage("studioBlockStart") private var studioBlockStart: Int = 8
    @AppStorage("studioBlockEnd") private var studioBlockEnd: Int = 20
    @AppStorage("toudouBaseURL") private var toudouBaseURL: String = "https://toudou-one.vercel.app"

    @State private var apiKey: String = ""
    @State private var apiKeySaved: Bool = false
    @State private var toudouToken: String = ""
    @State private var toudouTokenSaved: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var notifAuthorized: Bool = false

    @State private var calendarAccess = false
    @State private var remindersAccess = false
    @State private var importMessage: String?
    @State private var noteNames: [String] = []
    @State private var loadingNotes = false
    @State private var calendars: [String] = []
    @State private var reminderLists: [String] = []

    // (slug WhisperKit exact, libellé). Slugs vérifiés sur le repo argmaxinc/whisperkit-coreml.
    private let models: [(slug: String, label: String)] = [
        ("tiny", "Tiny · ultra rapide, basique"),
        ("base", "Base · rapide (défaut)"),
        ("small", "Small · plus précis"),
        ("distil-whisper_distil-large-v3_turbo", "Distil Large v3 Turbo · précis, assez rapide"),
        ("openai_whisper-large-v3_turbo", "Large v3 Turbo · très précis, plus lent"),
        ("openai_whisper-large-v3", "Large v3 · précision max, le plus lent")
    ]

    var body: some View {
        Form {
            Section("Raccourci de capture") {
                KeyboardShortcuts.Recorder("Maintenir pour parler :", name: .capture)
                Text("Appui long = capture vocale. Appui bref = ouvre la liste.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Transcription") {
                Picker("Modèle Whisper", selection: $whisperModel) {
                    ForEach(models, id: \.slug) { Text($0.label).tag($0.slug) }
                }
                Text("Plus le modèle est gros, plus c'est précis mais lent (et lourd à télécharger au 1er usage). Les « Large » comprennent mieux les mots rares. Changement pris en compte au redémarrage.")
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
                        Picker("Agenda studio podcast", selection: $calendarStudio) { calendarOptions() }
                        HStack {
                            Picker("Fermeture studio : de", selection: $studioBlockStart) {
                                ForEach(0..<24, id: \.self) { Text("\($0)h").tag($0) }
                            }
                            Picker("à", selection: $studioBlockEnd) {
                                ForEach(0..<24, id: \.self) { Text("\($0)h").tag($0) }
                            }
                        }
                        Text("Quand tu fermes le studio sans heure précise, l'événement bloque cette plage (créneau réel, pas journée entière → bloque vraiment les réservations).")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Agenda par défaut", selection: $defaultCalendar) { calendarOptions() }
                        Toggle("Rappels auto sur les événements (1h + 1 jour avant)", isOn: $eventAlarmsEnabled)
                        Text("Le LLM classe chaque rdv (perso / commun / pro / studio) et l'ajoute à l'agenda choisi ici.")
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
                    HStack {
                        Picker("Note de courses", selection: $defaultNote) {
                            ForEach(noteOptions, id: \.self) { Text($0.isEmpty ? "Courses" : $0).tag($0) }
                        }
                        Button(loadingNotes ? "…" : "Charger") { loadNotes() }
                            .disabled(loadingNotes)
                    }
                    Text("Les courses dictées sont ajoutées en texte (une ligne par article) à cette note Apple. « Charger » liste tes notes (demande l'accès à Notes).")
                        .font(.caption).foregroundStyle(.secondary)

                    Text("Cible précise possible à la voix : « dans mon calendrier BoulouFlo », « dans ma liste Courses », « dans ma note Maison ».")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Règles de classement") {
                TextEditor(text: $customRoutingRules)
                    .font(.callout)
                    .frame(minHeight: 90)
                Text("Écris tes consignes en français, une par ligne. Le LLM les applique en priorité. Ex :\n• rdv kiné → agenda commun (Marion et Flo)\n• réservation ou fermeture du studio → agenda studio\n• tout ce qui parle de facture → mes rappels")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Démarrage") {
                Toggle("Ouvrir AssistToDo au démarrage", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
            }

            Section("Permissions système") {
                permissionRow("Microphone", granted: micStatus == .authorized) { requestMic() }
                permissionRow("Notifications", granted: notifAuthorized) { requestNotifications() }
            }

            Section("Synchronisation Toudou") {
                TextField("URL de l'API Toudou (https://…)", text: $toudouBaseURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                SecureField("Token Bearer", text: $toudouToken)
                HStack {
                    Button("Enregistrer le token") {
                        KeychainStore.setToudouToken(toudouToken)
                        toudouTokenSaved = KeychainStore.hasToudouToken
                        SyncCoordinator.shared?.start()   // (re)démarre la sync avec la nouvelle config
                    }
                    if toudouTokenSaved {
                        Label("Token enregistré", systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                Button("Synchroniser maintenant") { SyncCoordinator.shared?.syncNow() }
                Text("Synchronise ta liste de to-do « vide-tête » (sans date) avec Toudou, dans les deux sens (texte + coché). URL + token fournis par Toudou. Synchro auto toutes les ~45 s.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("À propos") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(UpdateChecker.currentVersion).foregroundStyle(.secondary)
                }
                Button("Vérifier les mises à jour") { UpdateChecker.check(manual: true) }
            }

            Section("Sauvegarde des préférences") {
                HStack {
                    Button("Exporter…") { PreferencesService.export() }
                    Button("Importer…") {
                        if PreferencesService.importFromFile() {
                            refresh()
                            importMessage = "Préférences importées. Redémarre l'app pour le raccourci."
                        }
                    }
                    if let msg = importMessage {
                        Text(msg).font(.caption).foregroundStyle(.green)
                    }
                }
                Text("Sauvegarde un fichier JSON (calendriers, listes, note, clé API, raccourci). Réimporte-le sur un autre Mac pour tout retrouver. Garde ce fichier en lieu sûr : il contient ta clé API.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: refresh)
    }

    private var noteOptions: [String] {
        var opts = noteNames
        if !defaultNote.isEmpty && !opts.contains(defaultNote) { opts.insert(defaultNote, at: 0) }
        if opts.isEmpty { opts = ["Courses"] }
        return opts
    }

    private func loadNotes() {
        loadingNotes = true
        Task {
            let names = await NotesService.shared.listNoteNames()
            await MainActor.run {
                noteNames = names
                loadingNotes = false
            }
        }
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
        toudouTokenSaved = KeychainStore.hasToudouToken
        if toudouToken.isEmpty { toudouToken = KeychainStore.toudouToken() }
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
