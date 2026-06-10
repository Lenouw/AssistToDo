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
        panel.show()
    }

    func end() {
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

            // Parsing → tâche(s) → notifs → persistance → toast.
            var records = await parser.parse(transcript: t.text, now: Date())
            for i in records.indices {
                if let id = notifications.schedule(for: records[i]) {
                    records[i].notificationId = id
                }
            }
            store.add(records)
            toast.show(records)
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
