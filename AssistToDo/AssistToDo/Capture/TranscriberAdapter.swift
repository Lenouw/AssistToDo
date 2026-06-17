//
//  TranscriberAdapter.swift
//  AssistToDo
//
//  Adapte `Transcriber` (Kit) au protocole `AudioTranscribing` attendu par `CaptureProcessor`.
//  Wrapper plutôt qu'extension : évite un clash avec `Transcriber.transcribe(path:) -> Transcription?`.
//

import Foundation
import AssistToDoKit

@MainActor
struct TranscriberAdapter: AudioTranscribing {
    let transcriber: Transcriber
    func transcribe(path: String) async -> (text: String, avgLogProb: Float)? {
        guard transcriber.isReady, let r = await transcriber.transcribe(path: path) else { return nil }
        return (r.text, r.avgLogProb)
    }
}
