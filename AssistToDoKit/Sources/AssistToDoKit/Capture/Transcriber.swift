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
    /// Modèle réellement chargé (peut différer du modèle demandé en cas de repli).
    @Published public private(set) var loadedModel: String?

    private var whisper: WhisperKit?
    private let model: String
    /// Repli si le modèle demandé ne se réchauffe pas (tokenizer HF indispo, compile ANE, etc.).
    private static let fallbackModel = "openai_whisper-base"

    public struct Transcription {
        public let text: String
        public let avgLogProb: Float
    }

    public init(model: String) {
        self.model = model
        Task { await load() }
    }

    private func load() async {
        // Essaie le modèle demandé, puis le modèle de repli. Chaque essai n'est validé qu'après un
        // WARMUP réussi (une vraie mini-transcription) : ça force le téléchargement du tokenizer (HF)
        // + la compile CoreML, et garantit qu'isReady=true veut dire "transcrit vraiment".
        var tried = Set<String>()
        for candidate in [model, Self.fallbackModel]
            where !candidate.isEmpty && tried.insert(candidate).inserted {
            if await tryLoad(candidate) { return }
        }
        log.error("❌ aucun modèle Whisper n'a pu se charger (ni \(self.model, privacy: .public) ni le repli)")
    }

    private func tryLoad(_ m: String) async -> Bool {
        let wk: WhisperKit
        do {
            log.notice("chargement modèle \(m, privacy: .public)…")
            wk = try await WhisperKit(WhisperKitConfig(model: m))
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
