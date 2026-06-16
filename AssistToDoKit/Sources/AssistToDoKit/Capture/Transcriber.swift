//
//  Transcriber.swift
//  AssistToDoKit
//
//  Transcription offline via WhisperKit. Le modèle est pré-chargé au lancement
//  (téléchargé au 1er run). Transcrit le fichier audio en français.
//

import Foundation
import WhisperKit

@MainActor
public final class Transcriber: ObservableObject {
    @Published public private(set) var isReady = false

    private var whisper: WhisperKit?
    private let model: String

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
            whisper = try await WhisperKit(config)
            isReady = true
            print("WhisperKit prêt (modèle \(model))")
            // Préchauffe APRÈS coup, best-effort : compile le modèle CoreML / chauffe le Neural Engine
            // pour que la 1ʳᵉ capture ne soit pas lente (corrige le démarrage à froid). Séparé de l'init
            // → si ça échoue, isReady reste true et la transcription marche quand même.
            Task { [weak self] in try? await self?.whisper?.prewarmModels() }
        } catch {
            print("Erreur init WhisperKit: \(error)")
        }
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
            print("Erreur transcription: \(error)")
            return nil
        }
    }
}
