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
    /// État de préparation du modèle, pour piloter un bandeau avec progression réelle.
    public enum Readiness: Equatable {
        case downloading(Double)   // téléchargement HuggingFace, fraction 0…1
        case preparing             // chargement + préchauffage CoreML (indéterminé)
        case ready
        case failed
    }

    @Published public private(set) var isReady = false
    @Published public private(set) var readiness: Readiness = .downloading(0)

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
            // 1) Téléchargement explicite (avec progression réelle) pour alimenter le bandeau %.
            //    Si le modèle est déjà en cache, la progression saute vite à 100 %.
            readiness = .downloading(0)
            let folder = try await WhisperKit.download(variant: model) { [weak self] progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    if let self, case .downloading = self.readiness {
                        self.readiness = .downloading(fraction)
                    }
                }
            }
            // 2) Chargement en mémoire depuis le dossier téléchargé (pas de re-download). On charge
            //    SANS prewarm dans la config (prewarm:true faisait planter l'init → "indisponible").
            readiness = .preparing
            let config = WhisperKitConfig(model: model, modelFolder: folder.path, prewarm: false, download: false)
            let w = try await WhisperKit(config)
            whisper = w
            // PAS de prewarmModels() : WhisperKit(config) charge et compile déjà le modèle en mémoire
            // ici (loadModels par défaut). Le préchauffage n'était qu'un bonus de spécialisation, mais
            // il se bloquait indéfiniment sur certains modèles/appareils (Neural Engine) → modèle prêt
            // sans réponse. La compilation restante se fait à la 1ʳᵉ transcription (bornée par timeout).
            isReady = true
            readiness = .ready
            log.info("WhisperKit prêt (\(self.model, privacy: .public))")
        } catch {
            readiness = .failed
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
