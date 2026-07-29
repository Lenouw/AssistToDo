//
//  TranscriberAdapter.swift
//  AssistToDoiOS
//
//  Adapte `Transcriber` (Kit) au protocole `AudioTranscribing` attendu par `CaptureProcessor`.
//  Wrapper (pas extension) pour éviter le clash avec `Transcriber.transcribe(path:) -> Transcription?`.
//

import Foundation
import AssistToDoKit

@MainActor
struct TranscriberAdapter: AudioTranscribing {
    let transcriber: Transcriber
    /// Reflète l'état réel du moteur : le filet (CaptureProcessor) doit distinguer « pas encore prêt »
    /// (on attend, capture reste .recorded) d'un vrai échec. Sans ça = « échec » injustifié au warmup.
    var isReady: Bool { transcriber.isReady }
    func transcribe(path: String) async -> (text: String, avgLogProb: Float)? {
        guard transcriber.isReady, let r = await transcriber.transcribe(path: path) else { return nil }
        return (r.text, r.avgLogProb)
    }
}
