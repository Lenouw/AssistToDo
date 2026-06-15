import Foundation
import AssistToDoCore

/// Étages injectables du pipeline (pour testabilité hermétique).
public protocol AudioTranscribing {
    var isReady: Bool { get }
    func transcribe(path: String) async -> (text: String, avgLogProb: Float)?
}

public protocol TaskParsing {
    func parseTasks(transcript: String, now: Date) async -> [RoutedTask]
}

public protocol TaskRouting {
    /// Crée les items pour ces tâches routées, supprime `previous` (idempotence), retourne les nouveaux ids.
    func route(_ tasks: [RoutedTask], replacing previous: [UUID]) async -> [UUID]
}

extension TaskParser: TaskParsing {
    public func parseTasks(transcript: String, now: Date) async -> [RoutedTask] {
        await parse(transcript: transcript, now: now)
    }
}

/// Pipeline partagé d'une capture : transcription → garde-fou → parse → routage (injecté).
/// Rejouable et idempotent (remplace les items précédents via `producedTaskIds`).
@MainActor
public final class CaptureProcessor {
    private let store: CaptureStore
    private let transcriber: AudioTranscribing
    private let parser: TaskParsing
    private let router: TaskRouting

    public init(store: CaptureStore, transcriber: AudioTranscribing, parser: TaskParsing, router: TaskRouting) {
        self.store = store; self.transcriber = transcriber; self.parser = parser; self.router = router
    }

    /// Exécute (ou rejoue) le pipeline complet depuis l'audio de la capture.
    public func process(captureId: UUID, now: Date) async {
        guard let rec = store.captures.first(where: { $0.id == captureId }) else { return }
        let audioPath = CapturePaths.url(for: rec.audioFilename).path
        let previous = rec.producedTaskIds
        let duration = rec.durationSec
        store.update(id: captureId) { $0.status = .transcribing; $0.attempts += 1 }

        // 1) Transcription locale
        guard transcriber.isReady, let t = await transcriber.transcribe(path: audioPath) else {
            store.update(id: captureId) {
                $0.status = .failed(stage: "transcription", reason: "indisponible")
                $0.lastError = "transcription indisponible"
            }
            return
        }
        store.update(id: captureId) { $0.transcript = t.text; $0.status = .transcribed }

        // 2) Garde-fou local (bruit / hésitations)
        let verdict = HallucinationFilter.evaluate(transcript: t.text, audioDuration: duration, avgLogProb: Double(t.avgLogProb))
        if case .reject = verdict {
            store.update(id: captureId) { $0.status = .done; $0.parsedSummary = "(ignoré : bruit)" }
            return
        }

        // 3) Parse LLM (fallback texte brut intégré au parser si réseau KO)
        store.update(id: captureId) { $0.status = .routing }
        let routed = await parser.parseTasks(transcript: t.text, now: now)
        let producedSummary = routed.first?.record.text
        let needsEnrich = routed.contains { $0.record.parseStatus == .rawOnly }

        // 4) Routage injecté (spécifique plateforme), idempotent
        let newIds = await router.route(routed, replacing: previous)
        store.update(id: captureId) {
            $0.producedTaskIds = newIds
            $0.parsedSummary = producedSummary
            $0.needsEnrichment = needsEnrich
            $0.status = .done
        }
    }
}
