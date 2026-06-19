//
//  Transcriber.swift
//  AssistToDoKit
//
//  Transcription offline via WhisperKit. Le modèle est pré-chargé au lancement
//  (téléchargé au 1er run). Transcrit le fichier audio en français.
//

import Foundation
import os
import WhisperKit

@MainActor
public final class Transcriber: ObservableObject {
    @Published public private(set) var isReady = false

    private var whisper: WhisperKit?
    private let model: String
    private let log = Logger(subsystem: "com.assisttodo", category: "Transcriber")

    /// Sérialise prewarm ↔ transcribe. WhisperKit n'est pas réentrant sur une même instance :
    /// une transcription lancée pendant le préchauffage (1ᵉ capture après réinstall, cache CoreML
    /// vidé) se bloquait indéfiniment → spinner "Transcription…" infini. On préchauffe AVANT de
    /// signaler `isReady`, et ce drapeau empêche tout chevauchement résiduel.
    private var busy = false

    public struct Transcription {
        public let text: String
        public let avgLogProb: Float
    }

    public init(model: String) {
        self.model = model
        Task { await load() }
    }

    private func load() async {
        do {
            // On charge le modèle SANS prewarm dans la config (prewarm:true faisait planter l'init
            // sur certaines configs → "Transcription indisponible").
            let config = WhisperKitConfig(model: model)
            let w = try await WhisperKit(config)
            whisper = w
            log.info("WhisperKit modèle chargé (\(self.model, privacy: .public))")
            // Préchauffe AVANT de signaler prêt : compile le modèle CoreML / chauffe le Neural Engine.
            // Couvert par le bandeau "Préparation du modèle" → aucune transcription ne tourne pendant
            // ce temps (sinon blocage). Best-effort avec garde-fou de temps : si le prewarm traîne,
            // on passe quand même prêt (la 1ʳᵉ capture sera juste un peu plus lente).
            busy = true
            _ = await Self.withTimeout(seconds: 120) { [weak w] () -> Bool? in
                _ = try? await w?.prewarmModels()
                return true
            }
            busy = false
            isReady = true
            log.info("WhisperKit prêt")
        } catch {
            log.error("Erreur init WhisperKit: \(String(describing: error), privacy: .public)")
        }
    }

    public func transcribe(path: String) async -> Transcription? {
        guard let whisper, !busy else {
            log.error("Transcribe indisponible (chargé=\(self.whisper != nil), occupé=\(self.busy))")
            return nil
        }
        busy = true
        defer { busy = false }
        // Garde-fou de temps : si WhisperKit se fige, on renvoie nil au lieu de bloquer l'UI.
        // La capture reste journalisée (filet) → re-traitable depuis l'écran Captures.
        let result = await Self.withTimeout(seconds: 90) { [weak self] () -> Transcription? in
            guard let self else { return nil }
            do {
                let options = DecodingOptions(task: .transcribe, language: "fr", temperature: 0)
                let results = try await whisper.transcribe(audioPath: path, decodeOptions: options)
                let text = results
                    .map { $0.text }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let segments = results.flatMap { $0.segments }
                let avg = segments.isEmpty
                    ? 0
                    : segments.map { $0.avgLogprob }.reduce(0, +) / Float(segments.count)
                return Transcription(text: text, avgLogProb: avg)
            } catch {
                self.log.error("Erreur transcription: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        if result == nil { log.error("Transcription nulle (échec ou délai dépassé)") }
        return result
    }

    /// Exécute `work` avec un plafond de temps. Renvoie le résultat de `work`, ou `nil` si le délai
    /// expire d'abord. La tâche `work` n'est pas interrompue de force (WhisperKit ignore l'annulation),
    /// mais l'appelant n'est plus bloqué.
    private static func withTimeout<T>(seconds: Double, _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
