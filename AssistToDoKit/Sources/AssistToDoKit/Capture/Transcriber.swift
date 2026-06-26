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

    /// WhisperKit n'est pas réentrant sur une même instance. `busy` empêche deux transcriptions
    /// concurrentes. En cas de timeout, on N'autorise PAS une nouvelle transcription sur l'instance
    /// figée : on l'abandonne et on en recharge une neuve (voir `transcribe`).
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
            // 2) Chargement en mémoire depuis le dossier téléchargé (pas de re-download). PAS de
            //    prewarm (planter l'init / se figer sur certains Neural Engine) : WhisperKit(config)
            //    charge et compile déjà le modèle ; la compile restante se fait à la 1ʳᵉ transcription.
            readiness = .preparing
            let w = try await WhisperKit(WhisperKitConfig(model: model, modelFolder: folder.path,
                                                          prewarm: false, download: false))
            finishReady(w)
        } catch {
            // Repli : le chemin explicite (download:false + modelFolder) peut échouer sur cache
            // partiel/corrompu ou si la convention de dossier WhisperKit change. On laisse alors
            // WhisperKit résoudre/réparer son cache lui-même (download:true par défaut), au lieu de
            // rester bloqué sur « indisponible » jusqu'à réinstallation.
            log.error("Chargement explicite échoué (\(String(describing: error), privacy: .public)) → repli init WhisperKit")
            do {
                readiness = .preparing
                let w = try await WhisperKit(WhisperKitConfig(model: model, prewarm: false))
                finishReady(w)
            } catch {
                readiness = .failed
                log.error("Init WhisperKit échouée définitivement: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func finishReady(_ w: WhisperKit) {
        whisper = w
        isReady = true
        readiness = .ready
        log.info("WhisperKit prêt (\(self.model, privacy: .public))")
    }

    public func transcribe(path: String) async -> Transcription? {
        guard let whisper, !busy else {
            log.error("Transcribe indisponible (chargé=\(self.whisper != nil), occupé=\(self.busy))")
            return nil
        }
        busy = true
        // PAS de `defer { busy = false }` : sur timeout, whisper.transcribe continue de tourner
        // (WhisperKit ignore l'annulation). Remettre busy=false tout de suite laisserait une 2ᵉ
        // capture relancer transcribe sur l'instance figée → re-hang. On gère busy à la main selon
        // l'issue (succès → libère ; timeout → abandonne l'instance et recharge).
        let (value, timedOut) = await Self.withTimeout(seconds: 90) { [weak self] () -> Transcription? in
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
        if timedOut {
            // Instance figée : on l'abandonne (la tâche orpheline la garde en vie jusqu'à sa fin) et
            // on recharge une instance neuve. begin() bloque les captures tant que !isReady.
            log.error("Transcription figée (>90 s) → instance WhisperKit abandonnée, rechargement")
            self.whisper = nil
            isReady = false
            readiness = .preparing
            busy = false
            Task { await load() }
            return nil
        }
        busy = false
        if value == nil { log.error("Transcription nulle (échec)") }
        return value
    }

    /// Exécute `work` avec un plafond de temps. Renvoie `(résultat, timedOut)` : si le délai expire
    /// d'abord, `timedOut = true` et `value = nil`. La tâche `work` n'est pas interrompue de force
    /// (WhisperKit ignore l'annulation) ; l'appelant décide quoi faire de l'instance figée.
    private static func withTimeout<T>(seconds: Double, _ work: @escaping @Sendable () async -> T?) async -> (value: T?, timedOut: Bool) {
        await withTaskGroup(of: (T?, Bool).self) { group in
            group.addTask { (await work(), false) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return (nil, true)
            }
            let first = await group.next() ?? (nil, true)
            group.cancelAll()
            return first
        }
    }
}
