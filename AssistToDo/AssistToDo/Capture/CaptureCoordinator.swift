//
//  CaptureCoordinator.swift
//  AssistToDo
//
//  Orchestration de la capture : keyDown → arme le micro + montre le HUD,
//  keyUp → stoppe + ferme le HUD. (transcription + parsing branchés à l'étape suivante)
//

import AppKit

@MainActor
final class CaptureCoordinator {
    let audio = AudioCapture()
    let model = CaptureModel()
    private let panel: CapturePanelController
    private var activity: NSObjectProtocol?

    init() {
        panel = CapturePanelController(audio: audio, model: model)
    }

    func begin() {
        // Empêche l'App Nap de suspendre l'AVAudioEngine pendant la capture.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "capture vocale")
        model.state = .preparing
        audio.start()
        model.state = .listening
        panel.show()
    }

    func end() {
        let result = audio.stop()
        panel.hide()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }

        if !result.didDetectSpeech {
            NSSound.beep()
            print("Rien entendu (durée \(String(format: "%.1f", result.duration))s)")
        } else {
            print("Audio capté : \(String(format: "%.1f", result.duration))s, parole détectée")
        }
        // Prochaine étape : transcription WhisperKit + parsing OpenRouter + toast.
    }
}
