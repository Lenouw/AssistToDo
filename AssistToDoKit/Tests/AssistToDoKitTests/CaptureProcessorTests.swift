import XCTest
@testable import AssistToDoKit
@testable import AssistToDoCore

final class CaptureProcessorTests: XCTestCase {
    struct FakeTranscriber: AudioTranscribing {
        var isReady: Bool = true      // moteur chargé ?
        var succeeds: Bool = true     // la transcription réussit-elle (si prête) ?
        var text: String = ""
        func transcribe(path: String) async -> (text: String, avgLogProb: Float)? {
            succeeds ? (text, -0.2) : nil
        }
    }
    struct FakeParser: TaskParsing {
        let tasks: [RoutedTask]
        func parseTasks(transcript: String, now: Date) async -> [RoutedTask] { tasks }
    }
    final class FakeRouter: TaskRouting {
        var routed: [RoutedTask] = []
        var replaced: [UUID] = []
        func route(_ tasks: [RoutedTask], replacing previous: [UUID]) async -> [UUID] {
            routed = tasks; replaced = previous; return tasks.map { _ in UUID() }
        }
    }

    @MainActor
    func test_transcription_failure_keeps_audio_and_marks_failed() async throws {
        let store = try CaptureStore(inMemory: true)
        let rec = store.record(audioFilename: "x.caf", durationSec: 3)
        // Moteur PRÊT mais la transcription échoue → vrai échec.
        let proc = CaptureProcessor(store: store,
                                    transcriber: FakeTranscriber(isReady: true, succeeds: false),
                                    parser: FakeParser(tasks: []),
                                    router: FakeRouter())
        await proc.process(captureId: rec.id, now: Date())
        store.reload()
        if case .failed(let stage, _) = store.captures.first!.status {
            XCTAssertEqual(stage, "transcription")
        } else {
            XCTFail("devrait être failed:transcription")
        }
        XCTAssertEqual(store.captures.first!.audioFilename, "x.caf") // audio jamais perdu
    }

    @MainActor
    func test_model_not_ready_waits_without_failing() async throws {
        let store = try CaptureStore(inMemory: true)
        let rec = store.record(audioFilename: "x.caf", durationSec: 3)
        // Moteur PAS prêt (ex large-v3-turbo en warmup) → la capture attend, ne doit PAS échouer.
        let proc = CaptureProcessor(store: store,
                                    transcriber: FakeTranscriber(isReady: false),
                                    parser: FakeParser(tasks: []),
                                    router: FakeRouter())
        await proc.process(captureId: rec.id, now: Date())
        store.reload()
        let r = store.captures.first!
        XCTAssertEqual(r.status, .recorded)        // en attente, pas failed
        XCTAssertEqual(r.attempts, 0)              // aucune tentative consommée
        XCTAssertEqual(r.audioFilename, "x.caf")   // audio conservé pour le rejeu
    }

    @MainActor
    func test_success_routes_and_marks_done() async throws {
        let store = try CaptureStore(inMemory: true)
        let rec = store.record(audioFilename: "x.caf", durationSec: 3)
        let router = FakeRouter()
        let rt = RoutedTask(record: TaskRecord(text: "Appeler le plombier", createdAt: Date()),
                            destination: .local, durationMinutes: nil, listName: nil,
                            calendarName: nil, calendarCategory: nil, noteName: nil)
        let proc = CaptureProcessor(store: store,
                                    transcriber: FakeTranscriber(isReady: true, succeeds: true, text: "Penser à appeler le plombier"),
                                    parser: FakeParser(tasks: [rt]),
                                    router: router)
        await proc.process(captureId: rec.id, now: Date())
        store.reload()
        let r = store.captures.first!
        XCTAssertEqual(r.transcript, "Penser à appeler le plombier")
        XCTAssertEqual(router.routed.count, 1)
        XCTAssertEqual(r.status, .done)
        XCTAssertEqual(r.producedTaskIds.count, 1)
    }

    @MainActor
    func test_reroute_uses_existing_transcript_and_replaces_items() async throws {
        let store = try CaptureStore(inMemory: true)
        let rec = store.record(audioFilename: "x.caf", durationSec: 3)
        let oldId = UUID()
        store.update(id: rec.id) {
            $0.transcript = "Appeler le médecin demain"
            $0.status = .done
            $0.producedTaskIds = [oldId]
        }
        let router = FakeRouter()
        let rt = RoutedTask(record: TaskRecord(text: "Appeler le médecin", createdAt: Date()),
                            destination: .reminders, durationMinutes: nil, listName: nil,
                            calendarName: nil, calendarCategory: nil, noteName: nil)
        // Transcriber qui planterait s'il était appelé (reroute ne doit PAS transcrire).
        let proc = CaptureProcessor(store: store,
                                    transcriber: FakeTranscriber(isReady: false, succeeds: false),
                                    parser: FakeParser(tasks: [rt]),
                                    router: router)
        await proc.reroute(captureId: rec.id, now: Date())
        store.reload()
        XCTAssertEqual(router.replaced, [oldId])       // remplace les items précédents
        XCTAssertEqual(store.captures.first!.status, .done)
        XCTAssertEqual(store.captures.first!.producedTaskIds.count, 1)
    }
}
