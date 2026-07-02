//
//  SettingsView.swift
//  AssistToDo
//
//  Réglages : raccourci, transcription, intelligence (OpenRouter), destinations
//  (routage Rappels/Calendrier + défauts), démarrage, permissions.
//

import SwiftUI
import AssistToDoKit
import AVFoundation
import ServiceManagement
import UserNotifications
import KeyboardShortcuts

struct SettingsView: View {
    @AppStorage("whisperModel") private var whisperModel: String = "openai_whisper-small"
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
    @AppStorage("captureRetentionDays") private var captureRetentionDays: Int = 30
    @AppStorage("inappReminderNagEnabled") private var nagEnabled: Bool = true
    @AppStorage("inappReminderMorningMin") private var morningMin: Int = 630      // 10:30
    @AppStorage("inappReminderAfternoonMin") private var afternoonMin: Int = 930   // 15:30

    @State private var apiKey: String = ""
    @State private var apiKeySaved: Bool = false
    @State private var toudouToken: String = ""
    @State private var toudouTokenSaved: Bool = false
    @State private var showToudouAdvanced: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var notifAuthorized: Bool = false

    @State private var calendarAccess = false
    @State private var remindersAccess = false
    @State private var importMessage: String?

    @ObservedObject var transcriber: Transcriber
    @State private var testing = false
    @State private var testResult: TunnelResult?

    struct TunnelResult {
        var whisperOK: Bool; var whisperMsg: String
        var orOK: Bool; var orMsg: String
        var allOK: Bool { whisperOK && orOK }
    }
    @State private var noteNames: [String] = []
    @State private var loadingNotes = false
    @State private var calendars: [String] = []
    @State private var reminderLists: [String] = []

    // (slug WhisperKit exact, libellé). Slugs vérifiés sur le repo argmaxinc/whisperkit-coreml.
    private let models: [(slug: String, label: String)] = [
        ("openai_whisper-small", "Small · hors-ligne, réactif (défaut)"),
        ("openai_whisper-large-v3_turbo", "Large v3 Turbo · précision max (télécharge ~3 Go, 1 fois)"),
        ("base", "Base · minimal, ultra rapide")
    ]

    /// Pont entre des minutes-depuis-minuit (stockées) et une Date pour le DatePicker (heure Paris).
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return Binding(
            get: { cal.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
            set: { newDate in
                let c = cal.dateComponents([.hour, .minute], from: newDate)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    var body: some View {
        Form {
            Section("Diagnostic du tunnel") {
                Button {
                    Task { await runTunnelTest() }
                } label: {
                    HStack {
                        Image(systemName: "stethoscope")
                        Text("Tester le tunnel (transcription + IA)")
                        if testing { Spacer(); ProgressView().controlSize(.small) }
                    }
                }
                .disabled(testing)
                if let r = testResult {
                    Label(r.whisperOK ? "Transcription (Whisper) : OK" : "Transcription : \(r.whisperMsg)",
                          systemImage: r.whisperOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(r.whisperOK ? Color.green : Color.red).font(.system(size: 12))
                    Label(r.orOK ? "IA (OpenRouter / Gemini) : OK" : "IA : \(r.orMsg)",
                          systemImage: r.orOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(r.orOK ? Color.green : Color.red).font(.system(size: 12))
                    if r.allOK {
                        Text("✅ Tout fonctionne, le tunnel est opérationnel.")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                    }
                }
                Text("Vérifie que le modèle de transcription est chargé ET que l'IA répond avec ta clé. Rouge = c'est là que ça bloque.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Raccourci de capture") {
                KeyboardShortcuts.Recorder("Maintenir pour parler :", name: .capture)
                Text("Appui long = capture vocale. Appui bref = ouvre la liste.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Transcription") {
                Picker("Modèle Whisper", selection: $whisperModel) {
                    ForEach(models, id: \.slug) { Text($0.label).tag($0.slug) }
                }
                if transcriber.downloading {
                    HStack {
                        ProgressView(value: transcriber.downloadProgress > 0 ? transcriber.downloadProgress : nil)
                        Text("\(Int(transcriber.downloadProgress * 100)) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text("Téléchargement du modèle… (une seule fois)").font(.caption).foregroundStyle(.secondary)
                } else if whisperModel != transcriber.loadedModel {
                    Button("Télécharger et activer ce modèle") {
                        Task { await transcriber.switchModel(to: whisperModel) }
                    }
                    Text("Télécharge le modèle si besoin et l'active tout de suite, sans redémarrer.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if transcriber.isReady {
                    Label("Modèle actif : \(transcriber.loadedModel ?? whisperModel)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption)
                }
                Text("Plus le modèle est gros, plus c'est précis mais lourd. Small (défaut) est hors-ligne et réactif. Large v3 Turbo = précision max (~3 Go, téléchargé une fois).")
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

            Section("Relance des rappels (iCloud)") {
                Toggle("Me relancer tant que le rappel n'est pas fait", isOn: $nagEnabled)
                if nagEnabled {
                    DatePicker("Relance du matin", selection: timeBinding($morningMin), displayedComponents: .hourAndMinute)
                    DatePicker("Relance de l'après-midi", selection: timeBinding($afternoonMin), displayedComponents: .hourAndMinute)
                }
                Text("iCloud te notifie à l'heure du rappel. Une fois l'heure passée et tant que tu n'as pas coché, l'app prend le relais et te relance le matin + l'après-midi (sans modifier ton rappel iCloud).")
                    .font(.caption).foregroundStyle(.secondary)
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

            Section("Synchronisation perso (avancé)") {
                // Masqué par défaut : optionnel, nécessite ton PROPRE serveur Toudou.
                // Visible si un token est déjà enregistré (ton install) ou si tu l'ouvres.
                if toudouTokenSaved || showToudouAdvanced {
                    TextField("URL de l'API Toudou (https://…)", text: $toudouBaseURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                    SecureField("Token Bearer", text: $toudouToken)
                    HStack {
                        Button("Enregistrer le token") {
                            KeychainStore.setToudouToken(toudouToken)
                            toudouTokenSaved = KeychainStore.hasToudouToken
                            SyncCoordinator.shared?.start()
                        }
                        if toudouTokenSaved {
                            Label("Token enregistré", systemImage: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
                    }
                    Button("Resynchroniser tout") { SyncCoordinator.shared?.syncNow(full: true) }
                    Text("Synchronise tes listes « vide-tête » et « Claude Code » avec ton propre serveur Toudou (deux sens, texte + coché). Optionnel.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Configurer la synchronisation Toudou…") { showToudouAdvanced = true }
                    Text("Optionnel. Synchronise tes listes avec TON propre serveur Toudou. Pas nécessaire pour utiliser l'app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Captures (filet de sécurité)") {
                Picker("Garder les audios", selection: $captureRetentionDays) {
                    Text("7 jours").tag(7)
                    Text("30 jours").tag(30)
                    Text("90 jours").tag(90)
                    Text("Indéfiniment").tag(0)
                }
                Text("Chaque capture vocale est enregistrée durablement et rejouable (menu › Captures). Au-delà du délai, seul le fichier audio est supprimé (l'historique reste).")
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

    private func runTunnelTest() async {
        testing = true; defer { testing = false }
        testResult = nil
        // 1) Transcription : état réel du modèle chargé par l'app (warmup réussi = transcrit vraiment).
        let wOK = transcriber.isReady
        let loaded = transcriber.loadedModel ?? whisperModel
        let wMsg: String
        if transcriber.downloading {
            wMsg = "téléchargement du modèle en cours (1ʳᵉ fois, ~1 min)…"
        } else if wOK {
            wMsg = loaded == whisperModel ? "modèle « \(loaded) » chargé" : "repli sur « \(loaded) » (le modèle réglé n'a pas pu se charger)"
        } else {
            wMsg = "modèle « \(whisperModel) » pas encore prêt (compile / indispo)"
        }
        // 2) IA : vrai appel minimal à OpenRouter avec ta clé.
        var orOK = false; var orMsg = ""
        let orModel = UserDefaults.standard.string(forKey: "openRouterModel") ?? "google/gemini-2.5-flash"
        do {
            let resp = try await OpenRouterClient(model: orModel, timeout: 15)
                .complete(system: "Réponds uniquement: ok", user: "ping")
            orOK = !resp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            orMsg = orOK ? "réponse reçue" : "réponse vide"
        } catch {
            orMsg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        testResult = TunnelResult(whisperOK: wOK, whisperMsg: wMsg, orOK: orOK, orMsg: orMsg)
    }

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
