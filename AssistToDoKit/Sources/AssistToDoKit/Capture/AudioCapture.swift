//
//  AudioCapture.swift
//  AssistToDoKit
//
//  Capture micro via AVAudioEngine. Accumule les samples, publie un niveau (ondes),
//  et au stop NORMALISE l'audio au pic (auto-gain logiciel) avant transcription :
//  un micro à faible volume est remonté pour que Whisper entende fort.
//
//  Multiplateforme : sur iOS il faut activer une AVAudioSession (catégorie .record)
//  avant de démarrer le moteur ; sur macOS l'AVAudioSession n'existe pas.
//

import AVFoundation
import Combine

public final class AudioCapture: ObservableObject {
    private let engine = AVAudioEngine()

    /// Niveau audio normalisé 0…1 pour l'affichage des ondes.
    @Published public var level: Float = 0

    public private(set) var didDetectSpeech = false
    private var startTime: Date?

    private var samples: [Float] = []
    private var sampleRate: Double = 48_000
    private var peakRMS: Float = 0
    private let lock = NSLock()

    /// Seuil RMS (pic) sous lequel on considère qu'il n'y a pas eu de parole.
    private let speechThreshold: Float = 0.004
    /// Cible de normalisation (pic) et gain max (évite d'amplifier le bruit à fond).
    private let targetPeak: Float = 0.95
    private let maxGain: Float = 25

    public struct Result {
        public let duration: TimeInterval
        public let didDetectSpeech: Bool
        public let fileURL: URL?
    }

    public init() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            print("AVAudioEngine configuration change")
        }
    }

    // MARK: - Session iOS

    /// iOS : active une session d'enregistrement avant de démarrer le moteur. No-op sur macOS.
    private func activateSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("Erreur activation AVAudioSession: \(error)")
        }
        #endif
    }

    /// iOS : libère la session pour que les autres apps reprennent leur audio. No-op sur macOS.
    private func deactivateSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Erreur désactivation AVAudioSession: \(error)")
        }
        #endif
    }

    public func start() {
        // Déjà en capture : un 2e déclenchement (double-tap, auto + manuel) sans stop() entre les
        // deux relancerait le moteur en cours (engine.start() throw) et corromprait startTime/durée.
        guard !engine.isRunning else { return }
        // Reset SOUS le lock : didDetectSpeech / peakRMS sont aussi écrits par le tap audio
        // (autre thread). Les remettre à zéro hors lock = data race avec un buffer en vol.
        lock.lock()
        didDetectSpeech = false
        peakRMS = 0
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        DispatchQueue.main.async { self.level = 0 }

        activateSession()

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        sampleRate = format.sampleRate
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)

            var sum: Float = 0
            var local = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let s = channel[i]
                local[i] = s
                sum += s * s
            }
            let rms = count > 0 ? (sum / Float(count)).squareRoot() : 0

            self.lock.lock()
            self.samples.append(contentsOf: local)
            if rms > self.peakRMS { self.peakRMS = rms }
            if rms > self.speechThreshold { self.didDetectSpeech = true }
            self.lock.unlock()

            // Enveloppe : monte vite, descend doucement → ondes fluides (pas de clignotement
            // quand le volume retombe entre deux syllabes).
            let target = min(1, rms * 30)
            DispatchQueue.main.async {
                self.level = max(target, self.level * 0.82)
            }
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
    public func stop() -> Result {
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        startTime = nil
        DispatchQueue.main.async { self.level = 0 }
        deactivateSession()

        lock.lock()
        let captured = samples
        let peak = peakRMS
        let speech = didDetectSpeech
        lock.unlock()

        // Auto-gain : normalisation au VRAI pic d'échantillon (pas le RMS, qui est ~10-20 dB plus bas).
        // Normaliser sur le RMS sur-amplifiait les pics → saturation dès que le micro est à bon niveau.
        // Avec le vrai pic, le résultat plafonne à targetPeak (0.95) → jamais de clipping. Le boost
        // ne s'applique vraiment que pour un signal faible ; un signal déjà fort est juste calé à 0.95.
        let truePeak = captured.reduce(Float(0)) { Swift.max($0, abs($1)) }
        let gain = (speech && truePeak > 0) ? min(maxGain, targetPeak / truePeak) : 1
        if duration > 0.1 {  // pas de log pour les taps (durée ~0)
            print("AudioCapture: pic réel = \(String(format: "%.3f", truePeak)), RMS = \(String(format: "%.3f", peak)) (seuil \(speechThreshold)), gain ×\(String(format: "%.1f", gain)), parole=\(speech), durée=\(String(format: "%.1f", duration))s")
        }

        let url = speech ? writeNormalizedFile(captured, gain: gain) : nil
        return Result(duration: duration, didDetectSpeech: speech, fileURL: url)
    }

    /// Écrit un fichier mono float normalisé (au sample rate d'entrée ; WhisperKit resample).
    private func writeNormalizedFile(_ samples: [Float], gain: Float) -> URL? {
        guard !samples.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        let frames = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let dst = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<samples.count {
            dst[i] = max(-1, min(1, samples[i] * gain))
        }
        let filename = "assisttodo-\(UUID().uuidString).caf"
        let url = CapturePaths.url(for: filename)
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        } catch {
            print("Erreur écriture fichier audio: \(error)")
            return nil
        }
    }
}
