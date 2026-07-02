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
    private let log = Logger(subsystem: "com.assisttodo", category: "Transcriber")
    @Published public private(set) var isReady = false
    /// Vrai pendant un téléchargement de modèle (small offline, ou un modèle HF via switchModel).
    @Published public private(set) var downloading = false
    /// Progression 0…1 d'un téléchargement HF déclenché par switchModel (ex large-v3-turbo).
    @Published public private(set) var downloadProgress: Double = 0
    /// Modèle réellement chargé (peut différer du modèle demandé en cas de repli).
    @Published public private(set) var loadedModel: String?

    public typealias Provision = @Sendable () async -> (modelFolder: String, tokenizerFolder: URL)?

    private var whisper: WhisperKit?
    private var model: String
    /// Fournit le modèle offline « small » (téléchargé 1 fois depuis notre GitHub). Injecté par l'app.
    private let provision: Provision?
    /// Modèle offline provisionné, servant aussi de repli fiable si le modèle demandé échoue.
    private static let offlineModel = "openai_whisper-small"
    private static let fallbackModel = "openai_whisper-base"

    public struct Transcription {
        public let text: String
        public let avgLogProb: Float
    }

    public init(model: String, provision: Provision? = nil) {
        self.model = model
        self.provision = provision
        Task { await load() }
    }

    /// Change de modèle À CHAUD (depuis les Réglages), sans relancer l'app. Pour un modèle HF
    /// (ex large-v3-turbo), télécharge d'abord AVEC progression, puis recharge + warmup.
    public func switchModel(to newModel: String) async {
        guard newModel != loadedModel || !isReady else { return }
        isReady = false; whisper = nil; loadedModel = nil
        model = newModel
        if newModel != Self.offlineModel {   // modèle HF → pré-téléchargement avec %
            downloading = true; downloadProgress = 0
            do {
                _ = try await WhisperKit.download(variant: newModel, progressCallback: { [weak self] p in
                    Task { @MainActor in self?.downloadProgress = p.fractionCompleted }
                })
            } catch {
                log.error("téléchargement \(newModel, privacy: .public) : \(error.localizedDescription, privacy: .public)")
            }
            downloading = false
        }
        await load()
    }

    private func load() async {
        // 1) Modèle demandé. Si c'est le modèle offline (small) → chemins provisionnés (GitHub, sans HF).
        if model == Self.offlineModel {
            if await loadProvisioned() { return }
        } else if await tryLoad(model) {   // autres modèles (ex large-v3-turbo) → cache/HuggingFace
            return
        }
        // 2) Repli fiable : le small offline provisionné (aucun HF), sinon base via HF.
        if await loadProvisioned() { return }
        _ = await tryLoad(Self.fallbackModel)
        if !isReady { log.error("❌ aucun modèle Whisper n'a pu se charger") }
    }

    /// Charge « small » depuis les fichiers provisionnés (téléchargés 1 fois depuis notre GitHub),
    /// en OFFLINE total (download:false, tokenizer local). Télécharge d'abord si nécessaire.
    private func loadProvisioned() async -> Bool {
        guard let provision else { return false }
        downloading = true
        let paths = await provision()
        downloading = false
        guard let paths else { log.error("provisionnement du modèle offline échoué"); return false }
        return await tryLoad(Self.offlineModel, modelFolder: paths.modelFolder, tokenizerFolder: paths.tokenizerFolder)
    }

    private func tryLoad(_ m: String, modelFolder: String? = nil, tokenizerFolder: URL? = nil) async -> Bool {
        let wk: WhisperKit
        do {
            log.notice("chargement modèle \(m, privacy: .public)\(modelFolder == nil ? "" : " (offline)")…")
            // Dossiers fournis → offline (download:false). Sinon cache/HuggingFace.
            let config = WhisperKitConfig(model: m, modelFolder: modelFolder,
                                          tokenizerFolder: tokenizerFolder, download: modelFolder == nil)
            wk = try await WhisperKit(config)
        } catch {
            log.error("init \(m, privacy: .public) échoué : \(String(describing: error), privacy: .public)")
            return false
        }
        // Warmup avec retry : le tokenizer se télécharge en arrière-plan depuis HF au 1er usage
        // (erreur "tokenizerUnavailable" tant qu'il n'est pas là) → on retente en laissant le temps
        // au téléchargement avant d'abandonner ce modèle.
        let silence = [Float](repeating: 0, count: 16_000)   // ~1 s à 16 kHz
        let opts = DecodingOptions(task: .transcribe, language: "fr", temperature: 0)
        for attempt in 1...4 {
            do {
                _ = try await wk.transcribe(audioArray: silence, decodeOptions: opts)
                whisper = wk
                loadedModel = m
                isReady = true
                log.notice("✅ Whisper prêt (\(m, privacy: .public))\(m == self.model ? "" : " [repli]")")
                return true
            } catch {
                log.notice("warmup \(m, privacy: .public) tentative \(attempt, privacy: .public) : \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
            }
        }
        return false
    }

    public func transcribe(path: String) async -> Transcription? {
        guard let whisper else { return nil }
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
            log.error("transcription échouée : \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
