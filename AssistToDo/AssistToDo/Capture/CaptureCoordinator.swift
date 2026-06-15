//
//  CaptureCoordinator.swift
//  AssistToDo
//
//  Pipeline complet, affiché dans l'îlot (encoche) :
//  keyDown → micro + ondes ; keyUp → transcription → texte (gardé ~2s) → routage → ✓ ajouté.
//

import AppKit
import AssistToDoKit
import AssistToDoCore

@MainActor
final class CaptureCoordinator {
    let audio = AudioCapture()
    let model = CaptureModel()

    private let transcriber: Transcriber
    private let parser: TaskParser
    private let captureStore: CaptureStore          // journal des captures (filet de sécurité)
    private let macRouter: MacTaskRouter            // routage partagé (live + re-traitement)
    private let processor: CaptureProcessor         // pipeline rejouable (re-runs headless)
    private let island: IslandController
    private var activity: NSObjectProtocol?
    private var showTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    /// Incrémenté à chaque nouvelle capture : invalide les timers/états de la précédente.
    private var generation = 0

    init(transcriber: Transcriber, parser: TaskParser,
         captureStore: CaptureStore, macRouter: MacTaskRouter, processor: CaptureProcessor) {
        self.transcriber = transcriber
        self.parser = parser
        self.captureStore = captureStore
        self.macRouter = macRouter
        self.processor = processor
        island = IslandController(audio: audio, model: model)
    }

    /// Rejoue les captures en attente (échec LLM/routage ou texte brut à enrichir). Best-effort.
    func reprocessPending() {
        for rec in captureStore.needingProcessing() {
            let id = rec.id
            Task { [weak self] in await self?.processor.process(captureId: id, now: Date()) }
        }
    }

    func begin() {
        generation &+= 1               // nouvelle capture → invalide la précédente
        showTask?.cancel()
        workTask?.cancel()
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "capture vocale")
        model.transcript = ""
        model.addedItems = []
        model.state = transcriber.isReady ? .listening : .preparing
        audio.start()
        let gen = generation
        // Affiche l'îlot seulement après le seuil tap/hold (0,5s) : un appui bref (tap) n'affiche rien.
        showTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            self.island.show()
        }
    }

    /// Appui bref : on jette la capture, rien n'est transcrit ni créé.
    func cancel() {
        generation &+= 1
        showTask?.cancel()
        workTask?.cancel()
        _ = audio.stop()
        endActivity()
        hide()
    }

    func end() {
        showTask?.cancel()
        let result = audio.stop()
        endActivity()
        let gen = generation

        guard result.didDetectSpeech, let url = result.fileURL else {
            flashError("Rien entendu", beep: true, gen: gen)
            return
        }

        island.show()
        model.state = .transcribing

        // Journal (filet de sécurité) : la capture est enregistrée AVANT tout traitement.
        // L'audio (durable) est la source de vérité ; on met à jour le statut au fil du flux.
        let capId = captureStore.record(audioFilename: url.lastPathComponent, durationSec: result.duration).id

        workTask = Task { [weak self] in
            guard let self else { return }
            guard transcriber.isReady, let t = await transcriber.transcribe(path: url.path) else {
                self.captureStore.update(id: capId) { $0.status = .failed(stage: "transcription", reason: "indisponible") }
                self.flashError("Transcription indisponible", beep: true, gen: gen)
                return
            }
            guard gen == self.generation, !Task.isCancelled else { return }   // capture remplacée
            self.captureStore.update(id: capId) { $0.transcript = t.text; $0.status = .transcribed }

            let verdict = HallucinationFilter.evaluate(
                transcript: t.text, audioDuration: result.duration, avgLogProb: Double(t.avgLogProb)
            )
            guard case .accept = verdict else {
                self.captureStore.update(id: capId) { $0.status = .done; $0.parsedSummary = "(ignoré : bruit)" }
                if case .reject(let reason) = verdict { self.flashError("Ignoré (\(reason))", beep: true, gen: gen) }
                return
            }

            // 1) Affiche le texte transcrit.
            self.model.transcript = t.text
            self.model.state = .result

            // 2) Routage (le texte reste visible pendant l'appel LLM).
            let (items, producedIds, summary) = await self.route(transcript: t.text)
            guard gen == self.generation else { return }

            // 3) Garde le texte ~2s de plus.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard gen == self.generation else { return }

            // 4) Si rien à créer : on n'écrit rien (mais la capture reste tracée).
            if items.isEmpty {
                self.captureStore.update(id: capId) { $0.status = .done; $0.parsedSummary = "(rien créé)" }
                Self.appendDiscardedHistory(t.text)
                self.model.state = .ignored
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard gen == self.generation else { return }
                self.hide()
                return
            }

            // 5) Sinon, confirme l'ajout + journalise le résultat.
            self.captureStore.update(id: capId) {
                $0.producedTaskIds = producedIds; $0.parsedSummary = summary; $0.status = .done
            }
            self.model.addedItems = items
            self.model.state = .added
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard gen == self.generation else { return }
            self.hide()
        }
    }

    // MARK: - Routage

    private func route(transcript: String) async -> (items: [ToastItem], producedIds: [UUID], summary: String?) {
        let routingOn = UserDefaults.standard.object(forKey: "routingEnabled") as? Bool ?? true
        let customRules = UserDefaults.standard.string(forKey: "customRoutingRules") ?? ""
        let routed = await parser.parse(
            transcript: transcript, now: Date(),
            calendars: routingOn ? EventKitService.shared.calendarTitles : [],
            reminderLists: routingOn ? EventKitService.shared.reminderListTitles : [],
            customRules: routingOn ? customRules : ""
        )
        // Routage partagé (même logique que le re-traitement). Pas de remplacement en live (capture neuve).
        let outcomes = await macRouter.routeDetailed(routed, replacing: [])
        let items = outcomes.map { ToastItem(record: $0.record, destination: $0.destination, fellBack: $0.fellBack) }
        let producedIds = outcomes.compactMap { $0.storedId }
        return (items, producedIds, routed.first?.record.text)
    }

    // MARK: - Privé

    private func flashError(_ message: String, beep: Bool, gen: Int) {
        guard gen == generation else { return }
        if beep { NSSound.beep() }
        island.show()
        model.transcript = message
        model.state = .error
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard let self, gen == self.generation else { return }
            self.hide()
        }
    }

    private func hide() {
        island.hide()
        model.transcript = ""
        model.addedItems = []
        model.state = .preparing
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    /// Garde les captures ignorées en historique (texte), sans rien créer. Cappé à 50.
    private static func appendDiscardedHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var history = UserDefaults.standard.stringArray(forKey: "discardedHistory") ?? []
        history.append(trimmed)
        if history.count > 50 { history.removeFirst(history.count - 50) }
        UserDefaults.standard.set(history, forKey: "discardedHistory")
        print("Capture ignorée (rien créé) : \(trimmed)")
    }
}
