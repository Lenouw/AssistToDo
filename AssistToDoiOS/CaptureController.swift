//
//  CaptureController.swift
//  AssistToDoiOS
//
//  Pipeline de capture iPhone, branché sur le FILET DE SÉCURITÉ (journal CaptureStore + audio
//  durable + re-traitement). La capture LIVE tourne inline (réactivité UI + Live Activity) et
//  journalise chaque étape ; CaptureProcessor sert au re-traitement headless (relance auto +
//  écran Captures). Routage délégué à IOSTaskRouter (idempotent).
//

import Foundation
import SwiftUI
import AssistToDoCore
import AssistToDoKit

@MainActor
final class CaptureController: ObservableObject {

    enum Phase: Equatable {
        case idle, preparing, listening, transcribing, result, added, ignored
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var transcript: String = ""
    @Published private(set) var addedSummaries: [String] = []
    @Published var level: Float = 0

    let audio = AudioCapture()
    private let transcriber: Transcriber
    private let parser: TaskParser
    private let captureStore: CaptureStore
    private let router: IOSTaskRouter
    private let processor: CaptureProcessor
    private let liveActivity = LiveActivityController()

    private var generation = 0
    private var levelTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?

    init(transcriber: Transcriber, parser: TaskParser, captureStore: CaptureStore,
         router: IOSTaskRouter, processor: CaptureProcessor) {
        self.transcriber = transcriber
        self.parser = parser
        self.captureStore = captureStore
        self.router = router
        self.processor = processor
    }

    var isReady: Bool { transcriber.isReady }

    /// Rejoue les captures en attente (échec LLM/routage ou texte brut à enrichir). Best-effort.
    func reprocessPending() {
        for rec in captureStore.needingProcessing() {
            let id = rec.id
            Task { [weak self] in await self?.processor.process(captureId: id, now: Date()) }
        }
    }

    // MARK: - Cycle press-and-hold

    func begin() {
        generation &+= 1
        workTask?.cancel()
        transcript = ""
        addedSummaries = []
        // Modèle pas encore chargé (1er run = téléchargement) : ne PAS enregistrer dans le vide.
        guard transcriber.isReady else {
            let gen = generation
            phase = .error("Modèle en préparation, réessaie dans un instant")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard let self, gen == self.generation else { return }
                self.reset()
            }
            return
        }
        phase = .listening
        audio.start()
        liveActivity.start()
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.level = self.audio.level
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    func cancel() {
        generation &+= 1
        levelTask?.cancel()
        _ = audio.stop()
        liveActivity.end(phase: .ignored, detail: "")
        reset()
    }

    func end() {
        levelTask?.cancel()
        let result = audio.stop()
        let gen = generation

        guard result.didDetectSpeech, let url = result.fileURL else {
            flashError("Rien entendu", gen: gen)
            return
        }

        phase = .transcribing
        liveActivity.update(phase: .processing, detail: "Transcription…")

        // Journal (filet) : la capture est enregistrée AVANT tout traitement. L'audio (durable,
        // CapturePaths) est la source de vérité ; on met à jour le statut au fil du flux.
        let capId = captureStore.record(audioFilename: url.lastPathComponent, durationSec: result.duration).id

        workTask = Task { [weak self] in
            guard let self else { return }
            guard transcriber.isReady, let t = await transcriber.transcribe(path: url.path) else {
                self.captureStore.update(id: capId) { $0.status = .failed(stage: "transcription", reason: "indisponible") }
                self.flashError("Transcription indisponible", gen: gen)
                return
            }
            guard gen == self.generation, !Task.isCancelled else { return }
            self.captureStore.update(id: capId) { $0.transcript = t.text; $0.status = .transcribed }

            let verdict = HallucinationFilter.evaluate(
                transcript: t.text, audioDuration: result.duration, avgLogProb: Double(t.avgLogProb)
            )
            guard case .accept = verdict else {
                self.captureStore.update(id: capId) { $0.status = .done; $0.parsedSummary = "(ignoré : bruit)" }
                if case .reject(let reason) = verdict { self.flashError("Ignoré (\(reason))", gen: gen) }
                return
            }

            self.transcript = t.text
            self.phase = .result
            self.liveActivity.update(phase: .processing, detail: t.text)

            let (summaries, producedIds, summary) = await self.route(transcript: t.text)
            guard gen == self.generation else { return }

            if summaries.isEmpty {
                self.captureStore.update(id: capId) { $0.status = .done; $0.parsedSummary = "(rien créé)" }
                self.phase = .ignored
                self.liveActivity.end(phase: .ignored, detail: "Rien à créer")
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard gen == self.generation else { return }
                self.reset()
                return
            }

            self.captureStore.update(id: capId) {
                $0.producedTaskIds = producedIds; $0.parsedSummary = summary; $0.status = .done
            }
            self.addedSummaries = summaries
            self.phase = .added
            self.liveActivity.end(phase: .added, detail: summaries.first ?? "Ajouté")
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard gen == self.generation else { return }
            self.reset()
        }
    }

    // MARK: - Routage (via le routeur partagé, comme le re-traitement)

    private func route(transcript: String) async -> (summaries: [String], producedIds: [UUID], summary: String?) {
        let routingOn = UserDefaults.standard.object(forKey: "routingEnabled") as? Bool ?? true
        let customRules = UserDefaults.standard.string(forKey: "customRoutingRules") ?? ""
        let routed = await parser.parse(
            transcript: transcript, now: Date(),
            calendars: routingOn ? EventKitService.shared.calendarTitles : [],
            reminderLists: routingOn ? EventKitService.shared.reminderListTitles : [],
            customRules: routingOn ? customRules : ""
        )
        let outcomes = await router.routeDetailed(routed, replacing: [])
        return (outcomes.map(Self.summaryLine), outcomes.compactMap { $0.storedId }, routed.first?.record.text)
    }

    private static func summaryLine(_ o: RoutedOutcome) -> String {
        let icon: String
        switch o.destination {
        case .calendar:  icon = "📅"
        case .reminders: icon = "⏰"
        case .notes:     icon = "🛒"
        case .local:     icon = o.record.localList == .code ? "💻" : "🧠"
        }
        return "\(icon) \(o.record.text)"
    }

    // MARK: - Privé

    private func flashError(_ message: String, gen: Int) {
        guard gen == generation else { return }
        transcript = message
        phase = .error(message)
        liveActivity.end(phase: .ignored, detail: message)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self, gen == self.generation else { return }
            self.reset()
        }
    }

    private func reset() {
        phase = .idle
        transcript = ""
        addedSummaries = []
        level = 0
    }
}
