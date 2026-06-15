import XCTest
@testable import AssistToDoKit
@testable import AssistToDoCore

final class CaptureProcessorTests: XCTestCase {
    struct FakeTranscriber: AudioTranscribing {
        let ready: Bool; let text: String
        var isReady: Bool { ready }
        func transcribe(path: String) async -> (text: String, avgLogProb: Float)? {
            ready ? (text, -0.2) : nil
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
        let proc = CaptureProcessor(store: store,
                                    transcriber: FakeTranscriber(ready: false, text: ""),
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
    func test_success_routes_and_marks_done() async throws {
        let store = try CaptureStore(inMemory: true)
        let rec = store.record(audioFilename: "x.caf", durationSec: 3)
        let router = FakeRouter()
        let rt = RoutedTask(record: TaskRecord(text: "Appeler le plombier", createdAt: Date()),
                            destination: .local, durationMinutes: nil, listName: nil,
                            calendarName: nil, calendarCategory: nil, noteName: nil)
        let proc = CaptureProcessor(store: store,
                                    transcriber: FakeTranscriber(ready: true, text: "Penser à appeler le plombier"),
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
}
