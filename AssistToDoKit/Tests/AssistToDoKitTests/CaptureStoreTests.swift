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

    func test_capturePaths_directory_is_persistent_and_exists() throws {
        let dir = try CapturePaths.directory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertFalse(dir.path.contains("/tmp/"))
        let url = CapturePaths.url(for: "test.caf")
        XCTAssertEqual(url.lastPathComponent, "test.caf")
        XCTAssertEqual(url.deletingLastPathComponent().path, dir.path)
    }

    @MainActor
    func test_purge_removes_done_audio_older_than_retention() throws {
        let store = try CaptureStore(inMemory: true)
        let old = store.record(audioFilename: "old.caf", durationSec: 1)
        store.update(id: old.id) { $0.status = .done; $0.createdAt = Date().addingTimeInterval(-40 * 86_400) }
        store.purgeAudio(olderThanDays: 30)
        XCTAssertTrue(store.captures.first!.audioFilename.isEmpty)   // audio purgé, métadonnée gardée
        XCTAssertEqual(store.captures.count, 1)
    }

    @MainActor
    func test_purge_keeps_recent_audio() throws {
        let store = try CaptureStore(inMemory: true)
        let r = store.record(audioFilename: "recent.caf", durationSec: 1)
        store.update(id: r.id) { $0.status = .done }
        store.purgeAudio(olderThanDays: 30)
        XCTAssertEqual(store.captures.first!.audioFilename, "recent.caf")
    }
}
