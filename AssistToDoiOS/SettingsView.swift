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

    // Routage calendrier/rappels (mêmes clés UserDefaults que celles lues par IOSTaskRouter).
    @AppStorage("defaultCalendar") private var defaultCalendar = ""
    @AppStorage("defaultReminderList") private var defaultReminderList = ""
    @AppStorage("calendar_perso") private var calPerso = ""
    @AppStorage("calendar_commun") private var calCommun = ""
    @AppStorage("calendar_pro") private var calPro = ""
    @AppStorage("calendar_studio") private var calStudio = ""
    @AppStorage("studioBlockStart") private var studioStart = 8
    @AppStorage("studioBlockEnd") private var studioEnd = 20
    @AppStorage("customRoutingRules") private var customRules = ""

    // Relance des rappels en retard (2 notifs/jour) — mêmes clés que le Mac (lues par le Kit).
    @AppStorage("inappReminderNagEnabled") private var nagEnabled = true
    @AppStorage("inappReminderMorningMin") private var nagMorningMin = 630    // 10:30
    @AppStorage("inappReminderAfternoonMin") private var nagAfternoonMin = 930 // 15:30

    // Alarmes par défaut (minutes AVANT l'échéance ; -1 = aucune). 3 créneaux réglables.
    @AppStorage("eventAlarmMin1") private var evAlarm1 = 60      // 1 h avant
    @AppStorage("eventAlarmMin2") private var evAlarm2 = 1440    // 1 jour avant
    @AppStorage("eventAlarmMin3") private var evAlarm3 = 15      // 15 min avant
    @AppStorage("reminderAlarmMin1") private var remAlarm1 = -1  // aucun pré-rappel par défaut
    @AppStorage("reminderAlarmMin2") private var remAlarm2 = -1
    @AppStorage("reminderAlarmMin3") private var remAlarm3 = -1

    // Presets d'alarme (libellé, minutes avant ; -1 = aucune).
    private let alarmPresets: [(String, Int)] = [
        ("Aucune", -1), ("À l'heure", 0), ("5 min avant", 5), ("15 min avant", 15),
        ("30 min avant", 30), ("1 h avant", 60), ("2 h avant", 120),
        ("1 jour avant", 1440), ("2 jours avant", 2880), ("1 semaine avant", 10080)
    ]

    @State private var toudouToken = ""
    @State private var apiKey = ""
    @State private var savedFlash = false
    @State private var hiddenCalendars: Set<String> = []   // agendas masqués de la zone Agenda

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

                calendarSection
                agendaVisibilitySection

                Section("Affichage") {
                    Picker("Disposition de l'écran", selection: $iosLayout) {
                        Text("Segmentée (onglets en haut)").tag(AppLayout.segmented)
                        Text("Empilée (tout en scroll)").tag(AppLayout.stacked)
                    }
                    Text("Segmentée : une zone à la fois (À faire · Rappels · Agenda · Fait). Empilée : zones en scroll, historique via l'horloge.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                nagSection
                eventAlarmsSection
                reminderAlarmsSection

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
            .scrollContentBackground(.hidden)
            .background(Color.atdBg.ignoresSafeArea())
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
            .onAppear {
                toudouToken = KeychainStore.toudouToken()
                apiKey = KeychainStore.apiKey()
                hiddenCalendars = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendars") ?? [])
            }
            .alert("Enregistré", isPresented: $savedFlash) { Button("OK", role: .cancel) {} }
        }
    }

    // MARK: - Relance des rappels en retard
    //
    // 2 notifications par jour (matin + après-midi) pour chaque rappel iCloud EN RETARD, jusqu'à
    // validation. iCloud notifie le jour J ; l'app prend le relais ensuite. Mêmes clés que le Mac.

    private var nagSection: some View {
        Section {
            Toggle("Relancer les rappels en retard", isOn: $nagEnabled)
            if nagEnabled {
                DatePicker("Le matin à", selection: nagTimeBinding($nagMorningMin), displayedComponents: .hourAndMinute)
                DatePicker("L'après-midi à", selection: nagTimeBinding($nagAfternoonMin), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Relance des rappels")
        } footer: {
            Text("2 notifications par jour pour chaque rappel en retard, jusqu'à ce qu'il soit fait (boutons Fait / À demain sur la notification).")
        }
        .onChange(of: nagEnabled) { _, _ in model.notifications.rescheduleReminderNags() }
        .onChange(of: nagMorningMin) { _, _ in model.notifications.rescheduleReminderNags() }
        .onChange(of: nagAfternoonMin) { _, _ in model.notifications.rescheduleReminderNags() }
    }

    /// Binding Date ↔ minutes-depuis-minuit (Paris) pour les DatePickers d'heure de relance.
    private func nagTimeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                ParisCalendar.calendar.date(bySettingHour: minutes.wrappedValue / 60,
                                            minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = ParisCalendar.calendar.dateComponents([.hour, .minute], from: d)
                minutes.wrappedValue = (c.hour ?? 10) * 60 + (c.minute ?? 30)
            }
        )
    }

    // MARK: - Routage calendrier / rappels
    //
    // Mappe les catégories (perso/commun/pro/studio) vers de vrais calendriers Apple, comme le Mac.
    // Sans ça, un événement "studio" tombe sur le calendrier système par défaut.

    private var calendarSection: some View {
        Section("Calendrier & Rappels") {
            if !EventKitService.shared.hasCalendarAccess {
                Text("Autorise le calendrier (section Permissions) pour choisir tes calendriers.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                calendarPicker("Calendrier par défaut", $defaultCalendar)
                calendarPicker("Catégorie · Perso", $calPerso)
                calendarPicker("Catégorie · Commun", $calCommun)
                calendarPicker("Catégorie · Pro", $calPro)
                calendarPicker("Catégorie · Studio", $calStudio)
                Stepper("Studio ouvre à \(studioStart) h", value: $studioStart, in: 0...23)
                Stepper("Studio ferme à \(studioEnd) h", value: $studioEnd, in: 1...24)
            }
            if EventKitService.shared.hasRemindersAccess {
                Picker("Liste de rappels par défaut", selection: $defaultReminderList) {
                    Text("Système (défaut)").tag("")
                    ForEach(EventKitService.shared.reminderListTitles, id: \.self) { Text($0).tag($0) }
                }
            }
            TextField("Règles de routage perso (optionnel)", text: $customRules, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private func calendarPicker(_ label: String, _ selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            Text("Système (défaut)").tag("")
            ForEach(EventKitService.shared.calendarTitles, id: \.self) { Text($0).tag($0) }
        }
    }

    // MARK: - Agendas affichés dans la zone Agenda
    //
    // Décocher un agenda le masque de la zone Agenda (ex. l'agenda partagé d'un client comme
    // « Fluffy Cat Hotel »). Persisté dans UserDefaults("hiddenCalendars"), lu par ListsView.

    @ViewBuilder private var agendaVisibilitySection: some View {
        if EventKitService.shared.hasCalendarAccess, !EventKitService.shared.allEventCalendarTitles.isEmpty {
            Section {
                ForEach(EventKitService.shared.allEventCalendarTitles, id: \.self) { name in
                    Toggle(name, isOn: Binding(
                        get: { !hiddenCalendars.contains(name) },
                        set: { shown in
                            if shown { hiddenCalendars.remove(name) } else { hiddenCalendars.insert(name) }
                            UserDefaults.standard.set(Array(hiddenCalendars), forKey: "hiddenCalendars")
                            model.agendaVisibilityVersion += 1   // déclenche le refresh de la vue Agenda
                        }))
                }
            } header: {
                Text("Agendas affichés")
            } footer: {
                Text("Décoche un agenda pour le masquer de la zone Agenda.")
            }
        }
    }

    // MARK: - Alarmes (événements + pré-rappels)

    private var eventAlarmsSection: some View {
        Section {
            alarmPicker("Alarme 1", $evAlarm1)
            alarmPicker("Alarme 2", $evAlarm2)
            alarmPicker("Alarme 3", $evAlarm3)
        } header: {
            Text("Alarmes des événements")
        } footer: {
            Text("Jusqu'à 3 alarmes avant chaque événement de calendrier créé. « Aucune » désactive un créneau.")
        }
    }

    private var reminderAlarmsSection: some View {
        Section {
            alarmPicker("Pré-rappel 1", $remAlarm1)
            alarmPicker("Pré-rappel 2", $remAlarm2)
            alarmPicker("Pré-rappel 3", $remAlarm3)
        } header: {
            Text("Pré-rappels des rappels")
        } footer: {
            Text("Notifications AVANT l'heure du rappel (en plus de l'alarme à l'heure). « Aucune » = pas de pré-rappel.")
        }
    }

    private func alarmPicker(_ label: String, _ selection: Binding<Int>) -> some View {
        Picker(label, selection: selection) {
            ForEach(alarmPresets, id: \.1) { Text($0.0).tag($0.1) }
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
