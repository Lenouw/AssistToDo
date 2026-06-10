//
//  CaptureCoordinator.swift
//  AssistToDo
//
//  Pipeline complet : keyDown → micro + HUD ; keyUp → stop → transcription
//  → parsing OpenRouter → création de tâche(s) + notifs + toast de confirmation.
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
    private let toast: ToastController
    private let panel: CapturePanelController
    private var activity: NSObjectProtocol?
    private var showTask: Task<Void, Never>?

    init(transcriber: Transcriber, parser: TaskParser, store: TaskStore,
         notifications: NotificationManager, toast: ToastController) {
        self.transcriber = transcriber
        self.parser = parser
        self.store = store
        self.notifications = notifications
        self.toast = toast
        panel = CapturePanelController(audio: audio, model: model)
    }

    func begin() {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "capture vocale")
        model.transcript = ""
        model.state = transcriber.isReady ? .listening : .preparing
        audio.start()
        // Affiche le HUD seulement après un court délai : un appui bref (tap) n'affiche rien.
        showTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.panel.show()
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
            flashAndHide("Rien entendu", beep: true)
            return
        }

        model.state = .finishing
        model.transcript = ""

        Task {
            guard transcriber.isReady, let t = await transcriber.transcribe(path: url.path) else {
                flashAndHide("Transcription indisponible", beep: true)
                return
            }

            let verdict = HallucinationFilter.evaluate(
                transcript: t.text, audioDuration: result.duration, avgLogProb: Double(t.avgLogProb)
            )
            guard case .accept = verdict else {
                if case .reject(let reason) = verdict { flashAndHide("Ignoré (\(reason))", beep: true) }
                return
            }

            // Affiche brièvement la transcription dans le HUD, puis ferme.
            model.transcript = t.text
            try? await Task.sleep(nanoseconds: 600_000_000)
            hide()

            // Parsing → routage par destination → toast.
            let routingOn = UserDefaults.standard.object(forKey: "routingEnabled") as? Bool ?? true
            let defaultCalendar = UserDefaults.standard.string(forKey: "defaultCalendar")
            let defaultList = UserDefaults.standard.string(forKey: "defaultReminderList")
            let defaultNote = UserDefaults.standard.string(forKey: "defaultNote") ?? "Courses"
            let routed = await parser.parse(
                transcript: t.text, now: Date(),
                calendars: routingOn ? EventKitService.shared.calendarTitles : [],
                reminderLists: routingOn ? EventKitService.shared.reminderListTitles : []
            )
            var localRecords: [TaskRecord] = []
            var toastItems: [ToastItem] = []

            for var item in routed {
                // Si le routage est coupé, tout va en local.
                let destination = routingOn ? item.destination : .local
                switch destination {
                case .calendar:
                    do {
                        try await EventKitService.shared.createEvent(
                            title: item.record.text,
                            start: item.record.remindAt ?? Date(),
                            durationMinutes: item.durationMinutes ?? 60,
                            calendarName: item.calendarName,
                            defaultCalendarName: defaultCalendar
                        )
                        toastItems.append(ToastItem(record: item.record, destination: .calendar, fellBack: false))
                    } catch {
                        print("Calendrier indisponible (\(error)), fallback local")
                        item.record.notificationId = notifications.schedule(for: item.record)
                        localRecords.append(item.record)
                        toastItems.append(ToastItem(record: item.record, destination: .calendar, fellBack: true))
                    }
                case .reminders:
                    do {
                        try await EventKitService.shared.createReminder(
                            title: item.record.text,
                            due: item.record.remindAt ?? item.record.dueDate,
                            listName: item.listName,
                            defaultListName: defaultList
                        )
                        toastItems.append(ToastItem(record: item.record, destination: .reminders, fellBack: false))
                    } catch {
                        print("Rappels indisponibles (\(error)), fallback local")
                        item.record.notificationId = notifications.schedule(for: item.record)
                        localRecords.append(item.record)
                        toastItems.append(ToastItem(record: item.record, destination: .reminders, fellBack: true))
                    }
                case .notes:
                    do {
                        try await NotesService.shared.append(
                            item: item.record.text,
                            noteName: item.noteName ?? defaultNote
                        )
                        toastItems.append(ToastItem(record: item.record, destination: .notes, fellBack: false))
                    } catch {
                        print("Notes indisponibles (\(error)), fallback local")
                        item.record.notificationId = notifications.schedule(for: item.record)
                        localRecords.append(item.record)
                        toastItems.append(ToastItem(record: item.record, destination: .notes, fellBack: true))
                    }
                case .local:
                    item.record.notificationId = notifications.schedule(for: item.record)
                    localRecords.append(item.record)
                    toastItems.append(ToastItem(record: item.record, destination: .local, fellBack: false))
                }
            }

            if !localRecords.isEmpty { store.add(localRecords) }
            toast.show(toastItems)
        }
    }

    // MARK: - Privé

    private func flashAndHide(_ message: String, beep: Bool) {
        if beep { NSSound.beep() }
        model.state = .finishing
        model.transcript = message
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            hide()
        }
    }

    private func hide() {
        panel.hide()
        model.transcript = ""
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
