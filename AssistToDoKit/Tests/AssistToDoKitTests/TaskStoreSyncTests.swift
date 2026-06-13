//
//  TaskStoreSyncTests.swift
//  AssistToDoKitTests
//
//  Sémantique de synchro critique du store partagé : ops dérivées, LWW, tombstones,
//  exclusion des courses, déplacement de sous-liste. Store SwiftData in-memory, sans réseau.
//

import XCTest
import AssistToDoCore
@testable import AssistToDoKit

@MainActor
final class TaskStoreSyncTests: XCTestCase {

    private func makeStore() -> TaskStore { TaskStore(inMemory: true) }

    private func wireTasks(_ json: String) throws -> [WireTask] {
        try JSONDecoder().decode([WireTask].self, from: Data(json.utf8))
    }

    private func braindump(_ text: String, id: UUID = UUID()) -> TaskRecord {
        TaskRecord(id: id, text: text, createdAt: Date(), dueDate: Date(), localList: .braindump)
    }

    // MARK: - Dérivation des ops

    func testAddBraindumpProducesCreateOp() {
        let store = makeStore()
        store.add([braindump("acheter du pain")])
        XCTAssertEqual(store.thoughts.count, 1)
        let ops = store.collectPendingOps(for: .braindump)
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.kind, .create)
    }

    func testShoppingNeverSynced() {
        let store = makeStore()
        store.add([TaskRecord(text: "lait", createdAt: Date(), dueDate: Date(), localList: .shopping)])
        XCTAssertEqual(store.shoppingItems.count, 1)
        XCTAssertTrue(store.collectPendingOps(for: .braindump).isEmpty)
        XCTAssertTrue(store.collectPendingOps(for: .code).isEmpty)
    }

    func testCodeAndBraindumpRoutedToOwnChannels() {
        let store = makeStore()
        store.add([braindump("note cerveau")])
        store.add([TaskRecord(text: "refactor X", createdAt: Date(), dueDate: Date(), localList: .code)])
        XCTAssertEqual(store.collectPendingOps(for: .braindump).count, 1)
        XCTAssertEqual(store.collectPendingOps(for: .code).count, 1)
    }

    // MARK: - Pull / LWW

    func testApplyPulledInsertsServerMirror() throws {
        let store = makeStore()
        let id = UUID().uuidString
        let tasks = try wireTasks("""
        [{"id":"\(id)","text":"venu du serveur","done":false,"updatedAt":"2026-06-13T10:00:00.000Z","deleted":false}]
        """)
        store.applyPulled(tasks, forList: .braindump)
        XCTAssertEqual(store.thoughts.count, 1)
        XCTAssertEqual(store.thoughts.first?.text, "venu du serveur")
        // Miroir déjà connu du serveur → aucune op à repousser.
        XCTAssertTrue(store.collectPendingOps(for: .braindump).isEmpty)
    }

    func testLWWLocalDirtyNewerWins() throws {
        let store = makeStore()
        let id = UUID()
        store.add([braindump("version locale", id: id)])
        store.updateText(id: id, text: "version locale éditée")   // bump updatedAt + dirty
        let stale = try wireTasks("""
        [{"id":"\(id.uuidString)","text":"version serveur ancienne","done":false,"updatedAt":"2000-01-01T00:00:00.000Z","deleted":false}]
        """)
        store.applyPulled(stale, forList: .braindump)
        XCTAssertEqual(store.thoughts.first?.text, "version locale éditée")
    }

    func testLWWServerNewerWins() throws {
        let store = makeStore()
        let id = UUID()
        store.add([braindump("version locale", id: id)])
        let fresh = try wireTasks("""
        [{"id":"\(id.uuidString)","text":"version serveur récente","done":true,"updatedAt":"2999-01-01T00:00:00.000Z","deleted":false}]
        """)
        store.applyPulled(fresh, forList: .braindump)
        XCTAssertEqual(store.thoughts.first?.text, "version serveur récente")
        XCTAssertEqual(store.thoughts.first?.isDone, true)
        XCTAssertTrue(store.collectPendingOps(for: .braindump).isEmpty)   // plus dirty
    }

    func testPulledDeletionRemovesLocal() throws {
        let store = makeStore()
        let id = UUID()
        store.add([braindump("à effacer par le serveur", id: id)])
        store.applyPushApplied([AppliedResult(id: id.uuidString, status: "applied")])
        let del = try wireTasks("""
        [{"id":"\(id.uuidString)","text":"","done":false,"updatedAt":"2999-01-01T00:00:00.000Z","deleted":true}]
        """)
        store.applyPulled(del, forList: .braindump)
        XCTAssertTrue(store.thoughts.isEmpty)
    }

    // MARK: - Tombstones (delete propagé)

    func testDeleteKnownRemoteTombstonesThenClears() {
        let store = makeStore()
        let id = UUID()
        store.add([braindump("à supprimer", id: id)])
        store.applyPushApplied([AppliedResult(id: id.uuidString, status: "applied")])  // remoteKnown=true
        XCTAssertTrue(store.collectPendingOps(for: .braindump).isEmpty)

        store.delete(id: id)
        XCTAssertTrue(store.thoughts.isEmpty)                       // plus affiché
        let ops = store.collectPendingOps(for: .braindump)
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.kind, .delete)                    // delete en attente

        store.applyPushApplied([AppliedResult(id: id.uuidString, status: "applied")])
        XCTAssertTrue(store.collectPendingOps(for: .braindump).isEmpty)  // tombstone purgé
    }

    func testDeleteNeverRemoteHardDeletes() {
        let store = makeStore()
        let id = UUID()
        store.add([braindump("jamais poussé", id: id)])
        store.delete(id: id)                                        // pas remoteKnown → suppression dure
        XCTAssertTrue(store.thoughts.isEmpty)
        XCTAssertTrue(store.collectPendingOps(for: .braindump).isEmpty)
    }

    // MARK: - Déplacement de sous-liste

    func testMoveBraindumpToCode() {
        let store = makeStore()
        let id = UUID()
        store.add([braindump("idée dev", id: id)])
        store.moveToList(id: id, to: .code)
        XCTAssertEqual(store.codeTasks.count, 1)
        XCTAssertEqual(store.thoughts.count, 0)
        XCTAssertEqual(store.codeTasks.first?.text, "idée dev")
    }

    // MARK: - Dates Toudou

    func testToudouDateRoundTrip() {
        let parsed = ToudouClient.parseDate("2026-06-13T10:00:00.000Z")
        XCTAssertNotNil(parsed)
        let formatted = ToudouClient.formatDate(parsed!)
        XCTAssertNotNil(ToudouClient.parseDate(formatted))
    }

    func testToudouDateParsesPlainISO() {
        XCTAssertNotNil(ToudouClient.parseDate("2026-06-13T10:00:00Z"))   // sans fraction
    }
}
