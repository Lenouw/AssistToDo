//
//  AudioCapture.swift
//  AssistToDo
//
//  Capture micro via AVAudioEngine. Publie un niveau RMS (pour les ondes du HUD)
//  et un drapeau VAD (du son a-t-il été détecté ?). Démarre au keyDown, stop au keyUp.
//

import AVFoundation
import Combine

final class AudioCapture: ObservableObject {
    private let engine = AVAudioEngine()

    /// Niveau audio normalisé 0…1 pour l'affichage des ondes.
    @Published var level: Float = 0

    private(set) var didDetectSpeech = false
    private var startTime: Date?
    private var audioFile: AVAudioFile?
    private var fileURL: URL?

    /// Seuil RMS au-dessus duquel on considère que l'utilisateur a parlé.
    private let speechThreshold: Float = 0.02

    struct Result {
        let duration: TimeInterval
        let didDetectSpeech: Bool
        let fileURL: URL?
    }

    init() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            // Changement de périphérique (AirPods, etc.) pendant la capture : on log, pas de crash.
            print("AVAudioEngine configuration change")
        }
    }

    func start() {
        didDetectSpeech = false
        DispatchQueue.main.async { self.level = 0 }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        // Fichier temporaire pour la transcription (WhisperKit lit + resample le fichier).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("assisttodo-\(UUID().uuidString).caf")
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            fileURL = url
        } catch {
            print("Erreur création fichier audio: \(error)")
            fileURL = nil
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)
            let rms = AudioCapture.rms(buffer)
            if rms > self.speechThreshold { self.didDetectSpeech = true }
            DispatchQueue.main.async { self.level = min(1, rms * 20) }
        }

        engine.prepare()
        do {
            try engine.start()
            startTime = Date()
        } catch {
            print("Erreur démarrage audio: \(error)")
        }
    }

    @discardableResult
    func stop() -> Result {
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil            // ferme et finalise le fichier
        let url = fileURL
        startTime = nil
        DispatchQueue.main.async { self.level = 0 }
        return Result(duration: duration, didDetectSpeech: didDetectSpeech, fileURL: url)
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let s = channel[i]
            sum += s * s
        }
        return (sum / Float(count)).squareRoot()
    }
}
