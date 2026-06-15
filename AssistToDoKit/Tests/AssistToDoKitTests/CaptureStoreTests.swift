import XCTest
@testable import AssistToDoKit

final class CaptureStoreTests: XCTestCase {
    func test_status_roundtrips_through_raw() {
        XCTAssertEqual(CaptureStatus(raw: "done"), .done)
        XCTAssertEqual(CaptureStatus(raw: "failed:llm:timeout").raw, "failed:llm:timeout")
        XCTAssertEqual(CaptureStatus(raw: "garbage"), .recorded) // défaut sûr
    }

    func test_captureRecord_defaults_to_recorded() {
        let r = CaptureRecord(id: UUID(), createdAt: Date(), audioFilename: "a.caf", durationSec: 2)
        XCTAssertEqual(CaptureStatus(raw: r.statusRaw), .recorded)
        XCTAssertEqual(r.attempts, 0)
        XCTAssertNil(r.transcript)
    }

    @MainActor
    func test_store_creates_and_queries_pending() throws {
        let store = try CaptureStore(inMemory: true)
        let id = store.record(audioFilename: "x.caf", durationSec: 3).id
        XCTAssertEqual(store.captures.count, 1)

        store.update(id: id) { $0.status = .transcribed; $0.needsEnrichment = true }
        let pending = store.needingProcessing()
        XCTAssertEqual(pending.map(\.id), [id])

        store.update(id: id) { $0.status = .done; $0.needsEnrichment = false }
        XCTAssertTrue(store.needingProcessing().isEmpty)
    }
}
