//
//  CaptureCoordinator.swift
//  AssistToDo
//
//  Orchestration de la capture : keyDown → arme le micro + HUD,
//  keyUp → stop → transcription WhisperKit → affichage dans le HUD.
//  (parsing OpenRouter + création de tâche = étape suivante)
//

import AppKit
import AssistToDoCore

@MainActor
final class CaptureCoordinator {
    let audio = AudioCapture()
    let model = CaptureModel()
    private let transcriber: Transcriber
    private let panel: CapturePanelController
    private var activity: NSObjectProtocol?

    init(transcriber: Transcriber) {
        self.transcriber = transcriber
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
            switch verdict {
            case .accept:
                model.transcript = t.text
                print("Transcript : \(t.text)")
                // Prochaine étape : parsing OpenRouter → création de tâche → toast.
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                hide()
            case .reject(let reason):
                flashAndHide("Ignoré (\(reason))", beep: true)
            }
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
