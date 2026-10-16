//
//  Transcriber.swift
//  AssistToDoKit
//
//  Transcription offline via whisper.cpp (ggml + Metal). Le modèle GGML est chargé par mmap
//  (quasi instantané, aucune compilation ANE, contrairement à CoreML/WhisperKit). Le .bin est
//  provisionné une seule fois depuis notre GitHub. Transcrit le fichier audio en français.
//

import Foundation
import os

@MainActor
public final class Transcriber: ObservableObject {
    private let log = Logger(subsystem: "com.assisttodo", category: "Transcriber")
    @Published public private(set) var isReady = false
    /// Vrai pendant le provisionnement/téléchargement du modèle GGML.
    @Published public private(set) var downloading = false
    /// Progression 0…1 du téléchargement du modèle (874 Mo au 1er lancement).
    @Published public private(set) var downloadProgress: Double = 0
    /// Modèle réellement chargé.
    @Published public private(set) var loadedModel: String?

    /// Fournit le chemin local du `.bin` GGML (téléchargé 1 fois depuis notre GitHub), en
    /// rapportant la progression du téléchargement. Injecté par l'app.
    public typealias Provision = @Sendable (_ progress: @escaping @Sendable (Double) -> Void) async -> URL?

    private var ctx: WhisperCppContext?
    private var model: String
    private let provision: Provision?

    public struct Transcription {
        public let text: String
        public let avgLogProb: Float
    }

    public init(model: String, provision: Provision? = nil) {
        self.model = model
        self.provision = provision
        Task { await load() }
    }

    /// Recharge le modèle (depuis les Réglages). whisper.cpp charge par mmap → rapide, pas de warmup.
    public func switchModel(to newModel: String) async {
        guard newModel != loadedModel || !isReady else { return }
        isReady = false; ctx = nil; loadedModel = nil
        model = newModel
        await load()
    }

    private func load() async {
        guard let provision else { log.error("aucun provisionnement de modèle injecté"); return }
        downloading = true; downloadProgress = 0
        let path = await provision { [weak self] p in
            Task { @MainActor in self?.downloadProgress = p }
        }
        downloading = false
        guard let path else { log.error("provisionnement du modèle GGML échoué"); return }
        Perf.mark(.modelProvisioned)
        do {
            // HORS du fil principal : whisper_init lit le .bin (874 Mo, relu du disque quand le
            // système a vidé le cache) et initialise Metal. Sur le fil principal (Transcriber est
            // @MainActor), ça gelait l'interface au lancement : 0,6 à 14 s mesurés sur le Mac,
            // 1 à 19 s au simulateur iPhone.
            Perf.mark(.modelInitStart)
            let modelPath = path.path
            let c = try await Task.detached(priority: .userInitiated) {
                try WhisperCppContext.create(modelPath: modelPath)
            }.value
            Perf.mark(.modelInitEnd)
            ctx = c
            loadedModel = model
            isReady = true
            log.notice("✅ whisper.cpp prêt (\(self.model, privacy: .public))")
            // Préchauffage : une transcription de 1 s de silence compile les noyaux Metal et alloue
            // les tampons, pour que la 1ʳᵉ vraie dictée soit aussi rapide que les suivantes.
            // Le contexte est un acteur : une dictée arrivée entre-temps attend simplement la fin.
            // Pas sur simulateur : sans GPU, la fenêtre de 30 s de whisper coûte ~50 s de CPU et
            // retarde la 1ʳᵉ vraie dictée. Sur iPhone (Metal), son coût est mesuré (« Modèle préchauffé »).
            #if !targetEnvironment(simulator)
            Task.detached(priority: .utility) {
                _ = try? await c.transcribe(samples: [Float](repeating: 0, count: 16_000), language: "fr")
                Perf.mark(.modelWarm)
            }
            #endif
        } catch {
            log.error("init whisper.cpp échoué : \(String(describing: error), privacy: .public)")
        }
    }

    public func transcribe(path: String) async -> Transcription? {
        guard let ctx else { return nil }
        guard let samples = AudioSamples16k.load(path: path) else {
            log.error("décodage audio 16 kHz échoué"); return nil
        }
        do {
            let r = try await ctx.transcribe(samples: samples, language: "fr")
            return Transcription(text: r.text, avgLogProb: r.avgLogProb)
        } catch {
            log.error("transcription échouée : \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
