//
//  CaptureCoordinator.swift
//  AssistToDo
//
//  Pipeline complet, affiché dans l'îlot (encoche) :
//  keyDown → micro + ondes ; keyUp → transcription → texte (gardé ~2s) → routage → ✓ ajouté.
//

import AppKit
import AssistToDoCore

@MainActor
final class CaptureCoordinator {
    let audio = AudioCapture()
    let model = CaptureModel()

    private let transcriber: Transcriber
    private let parser: TaskParser
    private let store: TaskStore
    private let notifications: NotificationManager
    private let island: IslandController
    private var activity: NSObjectProtocol?
    private var showTask: Task<Void, Never>?

    init(transcriber: Transcriber, parser: TaskParser, store: TaskStore,
         notifications: NotificationManager) {
        self.transcriber = transcriber
        self.parser = parser
        self.store = store
        self.notifications = notifications
        island = IslandController(audio: audio, model: model)
    }

    func begin() {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "capture vocale")
        model.transcript = ""
        model.addedItems = []
        model.state = transcriber.isReady ? .listening : .preparing
        audio.start()
        // Affiche l'îlot seulement après le seuil tap/hold (0,5s) : un appui bref (tap) n'affiche rien.
        showTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.island.show()
        }
    }

    /// Appui bref : on jette la capture, rien n'est transcrit ni créé.
    func cancel() {
        showTask?.cancel()
        _ = audio.stop()
        endActivity()
        hide()
    }

    func end() {
        showTask?.cancel()
        let result = audio.stop()
        endActivity()

        guard result.didDetectSpeech, let url = result.fileURL else {
            flashError("Rien entendu", beep: true)
            return
        }

        island.show()
        model.state = .transcribing

        Task {
            guard transcriber.isReady, let t = await transcriber.transcribe(path: url.path) else {
                flashError("Transcription indisponible", beep: true)
                return
            }

            let verdict = HallucinationFilter.evaluate(
                transcript: t.text, audioDuration: result.duration, avgLogProb: Double(t.avgLogProb)
            )
            guard case .accept = verdict else {
                if case .reject(let reason) = verdict { flashError("Ignoré (\(reason))", beep: true) }
                return
            }

            // 1) Affiche le texte transcrit.
            model.transcript = t.text
            model.state = .result

            // 2) Routage (le texte reste visible pendant l'appel LLM).
            let items = await route(transcript: t.text)

            // 3) Garde le texte ~2s de plus.
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // 4) Si rien à créer (LLM a jugé que ce n'est pas une vraie tâche) : on n'écrit rien.
            if items.isEmpty {
                Self.appendDiscardedHistory(t.text)
                model.state = .ignored
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                hide()
                return
            }

            // 5) Sinon, confirme l'ajout.
            model.addedItems = items
            model.state = .added
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            hide()
        }
    }

    // MARK: - Routage

    private func route(transcript: String) async -> [ToastItem] {
        let routingOn = UserDefaults.standard.object(forKey: "routingEnabled") as? Bool ?? true
        let defaultCalendar = UserDefaults.standard.string(forKey: "defaultCalendar")
        let defaultList = UserDefaults.standard.string(forKey: "defaultReminderList")
        let defaultNote = UserDefaults.standard.string(forKey: "defaultNote") ?? "Courses"

        let customRules = UserDefaults.standard.string(forKey: "customRoutingRules") ?? ""
        let routed = await parser.parse(
            transcript: transcript, now: Date(),
            calendars: routingOn ? EventKitService.shared.calendarTitles : [],
            reminderLists: routingOn ? EventKitService.shared.reminderListTitles : [],
            customRules: routingOn ? customRules : ""
        )

        var toStore: [TaskRecord] = []
        var items: [ToastItem] = []

        func keepLocal(_ rec: TaskRecord) -> TaskRecord {
            var r = rec
            r.destination = .local
            r.notificationId = notifications.schedule(for: r)
            return r
        }

        for item in routed {
            let destination = routingOn ? item.destination : .local
            switch destination {
            case .calendar:
                do {
                    let categoryCalendar = item.calendarCategory.flatMap { cat in
                        UserDefaults.standard.string(forKey: "calendar_\(cat.rawValue)")
                    }
                    let alarmsOn = UserDefaults.standard.object(forKey: "eventAlarmsEnabled") as? Bool ?? true
                    let offsets: [TimeInterval] = alarmsOn ? [-3600, -86400] : []  // 1h + 1 jour avant
                    let extId = try await EventKitService.shared.createEvent(
                        title: item.record.text,
                        start: item.record.remindAt ?? Date(),
                        durationMinutes: item.durationMinutes ?? 60,
                        calendarName: item.calendarName ?? categoryCalendar,
                        defaultCalendarName: defaultCalendar,
                        alarmOffsets: offsets
                    )
                    var r = item.record; r.destination = .calendar; r.externalId = extId
                    toStore.append(r)
                    items.append(ToastItem(record: r, destination: .calendar, fellBack: false))
                } catch {
                    print("Calendrier indisponible (\(error)), fallback local")
                    toStore.append(keepLocal(item.record))
                    items.append(ToastItem(record: item.record, destination: .calendar, fellBack: true))
                }
            case .reminders:
                do {
                    let extId = try await EventKitService.shared.createReminder(
                        title: item.record.text,
                        due: item.record.remindAt ?? item.record.dueDate,
                        listName: item.listName,
                        defaultListName: defaultList
                    )
                    var r = item.record; r.destination = .reminders; r.externalId = extId
                    toStore.append(r)
                    items.append(ToastItem(record: r, destination: .reminders, fellBack: false))
                } catch {
                    print("Rappels indisponibles (\(error)), fallback local")
                    toStore.append(keepLocal(item.record))
                    items.append(ToastItem(record: item.record, destination: .reminders, fellBack: true))
                }
            case .notes:
                do {
                    try await NotesService.shared.append(item: item.record.text, noteName: item.noteName ?? defaultNote)
                    items.append(ToastItem(record: item.record, destination: .notes, fellBack: false))
                } catch {
                    print("Notes indisponibles (\(error)), fallback local")
                    toStore.append(keepLocal(item.record))
                    items.append(ToastItem(record: item.record, destination: .notes, fellBack: true))
                }
            case .local:
                toStore.append(keepLocal(item.record))
                items.append(ToastItem(record: item.record, destination: .local, fellBack: false))
            }
        }

        if !toStore.isEmpty { store.add(toStore) }
        return items
    }

    // MARK: - Privé

    private func flashError(_ message: String, beep: Bool) {
        if beep { NSSound.beep() }
        island.show()
        model.transcript = message
        model.state = .error
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            hide()
        }
    }

    private func hide() {
        island.hide()
        model.transcript = ""
        model.addedItems = []
        model.state = .preparing
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    /// Garde les captures ignorées en historique (texte), sans rien créer. Cappé à 50.
    private static func appendDiscardedHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var history = UserDefaults.standard.stringArray(forKey: "discardedHistory") ?? []
        history.append(trimmed)
        if history.count > 50 { history.removeFirst(history.count - 50) }
        UserDefaults.standard.set(history, forKey: "discardedHistory")
        print("Capture ignorée (rien créé) : \(trimmed)")
    }
}
