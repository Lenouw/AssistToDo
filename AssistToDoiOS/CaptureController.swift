//
//  CaptureController.swift
//  AssistToDoiOS
//
//  Pipeline de capture iPhone (équivalent du CaptureCoordinator macOS, sans l'îlot AppKit) :
//  press-and-hold → micro + ondes → relâche → transcription locale → garde-fou →
//  structuration LLM → routage → stockage / Rappels / Calendrier / liste de courses in-app.
//  L'état (écoute → traitement → ajouté) pilote une Live Activity (Dynamic Island).
//

import Foundation
import SwiftUI
import AssistToDoCore
import AssistToDoKit

@MainActor
final class CaptureController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case preparing
        case listening
        case transcribing
        case result
        case added
        case ignored
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var transcript: String = ""
    @Published private(set) var addedSummaries: [String] = []
    /// Niveau micro 0…1 pour les ondes (relayé depuis AudioCapture).
    @Published var level: Float = 0

    let audio = AudioCapture()
    private let transcriber: Transcriber
    private let parser: TaskParser
    private let store: TaskStore
    private let notifications: NotificationManager
    private let liveActivity = LiveActivityController()

    private var generation = 0
    private var levelTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?

    init(transcriber: Transcriber, parser: TaskParser, store: TaskStore, notifications: NotificationManager) {
        self.transcriber = transcriber
        self.parser = parser
        self.store = store
        self.notifications = notifications
    }

    var isReady: Bool { transcriber.isReady }

    // MARK: - Cycle press-and-hold

    func begin() {
        generation &+= 1
        workTask?.cancel()
        transcript = ""
        addedSummaries = []
        // Modèle pas encore chargé (1er run = téléchargement) : ne PAS enregistrer dans le vide
        // (la capture serait perdue à la transcription). Message + retour à l'état repos.
        guard transcriber.isReady else {
            let gen = generation
            phase = .error("Modèle en préparation, réessaie dans un instant")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard let self, gen == self.generation else { return }
                self.reset()
            }
            return
        }
        phase = .listening
        audio.start()
        liveActivity.start()
        // Relaye le niveau micro vers l'UI (l'app, contrairement au Mac, observe directement).
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.level = self.audio.level
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    /// Annule (appui trop bref) : rien n'est transcrit ni créé.
    func cancel() {
        generation &+= 1
        levelTask?.cancel()
        _ = audio.stop()
        liveActivity.end(phase: .ignored, detail: "")
        reset()
    }

    func end() {
        levelTask?.cancel()
        let result = audio.stop()
        let gen = generation

        guard result.didDetectSpeech, let url = result.fileURL else {
            flashError("Rien entendu", gen: gen)
            return
        }

        phase = .transcribing
        liveActivity.update(phase: .processing, detail: "Transcription…")

        workTask = Task { [weak self] in
            guard let self else { return }
            guard let t = await transcriber.transcribe(path: url.path), transcriber.isReady else {
                self.flashError("Transcription indisponible", gen: gen)
                return
            }
            guard gen == self.generation, !Task.isCancelled else { return }

            let verdict = HallucinationFilter.evaluate(
                transcript: t.text, audioDuration: result.duration, avgLogProb: Double(t.avgLogProb)
            )
            guard case .accept = verdict else {
                if case .reject(let reason) = verdict { self.flashError("Ignoré (\(reason))", gen: gen) }
                return
            }

            self.transcript = t.text
            self.phase = .result
            self.liveActivity.update(phase: .processing, detail: t.text)

            let summaries = await self.route(transcript: t.text)
            guard gen == self.generation else { return }

            if summaries.isEmpty {
                self.phase = .ignored
                self.liveActivity.end(phase: .ignored, detail: "Rien à créer")
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard gen == self.generation else { return }
                self.reset()
                return
            }

            self.addedSummaries = summaries
            self.phase = .added
            self.liveActivity.end(phase: .added, detail: summaries.first ?? "Ajouté")
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard gen == self.generation else { return }
            self.reset()
        }
    }

    // MARK: - Routage (équivalent macOS, mais courses → liste in-app, jamais Apple Notes)

    private func route(transcript: String) async -> [String] {
        let routingOn = UserDefaults.standard.object(forKey: "routingEnabled") as? Bool ?? true
        let defaultCalendar = UserDefaults.standard.string(forKey: "defaultCalendar")
        let defaultList = UserDefaults.standard.string(forKey: "defaultReminderList")
        let customRules = UserDefaults.standard.string(forKey: "customRoutingRules") ?? ""

        let routed = await parser.parse(
            transcript: transcript, now: Date(),
            calendars: routingOn ? EventKitService.shared.calendarTitles : [],
            reminderLists: routingOn ? EventKitService.shared.reminderListTitles : [],
            customRules: routingOn ? customRules : ""
        )

        var toStore: [TaskRecord] = []
        var summaries: [String] = []

        func keepLocal(_ rec: TaskRecord, list: LocalList = .braindump) -> TaskRecord {
            var r = rec
            r.destination = .local
            r.localList = list
            r.notificationId = notifications.schedule(for: r)
            return r
        }

        for item in routed {
            // Routage OFF = pas de dispatch Apple (calendrier/rappels → local), MAIS la liste de
            // courses (.notes → liste in-app) reste honorée : c'est de l'app, pas du routage Apple.
            var destination = routingOn ? item.destination : (item.destination == .notes ? .notes : .local)
            // Filet : un événement sans date/heure dictée ne va jamais sur "aujourd'hui" inventé.
            if destination == .calendar, item.record.dueDate == nil, item.record.remindAt == nil {
                destination = .reminders
            }
            switch destination {
            case .calendar:
                do {
                    let categoryCalendar = item.calendarCategory.flatMap { cat in
                        UserDefaults.standard.string(forKey: "calendar_\(cat.rawValue)")
                    }
                    let alarmsOn = UserDefaults.standard.object(forKey: "eventAlarmsEnabled") as? Bool ?? true
                    let offsets: [TimeInterval] = alarmsOn ? [-3600, -86400] : []
                    let day = item.record.dueDate ?? Date()
                    var start = item.record.remindAt ?? day
                    var duration = item.durationMinutes ?? 60
                    var allDay = item.record.remindAt == nil
                    if item.record.remindAt == nil, item.calendarCategory == .studio {
                        let sh = UserDefaults.standard.object(forKey: "studioBlockStart") as? Int ?? 8
                        let eh = UserDefaults.standard.object(forKey: "studioBlockEnd") as? Int ?? 20
                        start = ParisCalendar.calendar.date(bySettingHour: sh, minute: 0, second: 0, of: day) ?? day
                        duration = max(60, (eh - sh) * 60)
                        allDay = false
                    }
                    _ = try await EventKitService.shared.createEvent(
                        title: item.record.text, start: start, durationMinutes: duration, allDay: allDay,
                        calendarName: item.calendarName ?? categoryCalendar,
                        defaultCalendarName: defaultCalendar, alarmOffsets: offsets)
                    summaries.append("📅 \(item.record.text)")
                } catch {
                    print("Calendrier indisponible (\(error)), fallback local")
                    toStore.append(keepLocal(item.record)); summaries.append("📝 \(item.record.text)")
                }
            case .reminders:
                do {
                    let extId = try await EventKitService.shared.createReminder(
                        title: item.record.text, due: item.record.remindAt ?? item.record.dueDate,
                        listName: item.listName, defaultListName: defaultList)
                    var r = item.record; r.destination = .reminders; r.externalId = extId
                    toStore.append(r); summaries.append("⏰ \(item.record.text)")
                } catch {
                    print("Rappels indisponibles (\(error)), fallback local")
                    toStore.append(keepLocal(item.record)); summaries.append("📝 \(item.record.text)")
                }
            case .notes:
                // iOS : pas d'Apple Notes (AppleScript indisponible). Les courses vont dans la
                // liste de courses in-app (sous-liste locale "shopping"), cases cochables contrôlées.
                toStore.append(keepLocal(item.record, list: .shopping))
                summaries.append("🛒 \(item.record.text)")
            case .local:
                let list: LocalList = item.record.localList == .code ? .code : .braindump
                toStore.append(keepLocal(item.record, list: list))
                summaries.append((list == .code ? "💻 " : "🧠 ") + item.record.text)
            }
        }

        if !toStore.isEmpty { store.add(toStore) }
        return summaries
    }

    // MARK: - Privé

    private func flashError(_ message: String, gen: Int) {
        guard gen == generation else { return }
        transcript = message
        phase = .error(message)
        liveActivity.end(phase: .ignored, detail: message)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self, gen == self.generation else { return }
            self.reset()
        }
    }

    private func reset() {
        phase = .idle
        transcript = ""
        addedSummaries = []
        level = 0
    }
}
