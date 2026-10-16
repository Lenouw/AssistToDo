//
//  WorkSyncTests.swift
//  AssistToDoKitTests
//
//  Synchro de la liste Travail avec Toudou (slug « travail ») : client, priorité et échéance
//  partent avec la tâche et reviennent au pull ; rattrapage des tâches créées avant la synchro.
//

import XCTest
import AssistToDoCore
@testable import AssistToDoKit

@MainActor
final class WorkSyncTests: XCTestCase {

    private func work(_ text: String, project: String? = nil, priority: Priority? = nil, due: Date? = nil) -> TaskRecord {
        TaskRecord(text: text, createdAt: Date(), dueDate: due, priority: priority, localList: .work, projectName: project)
    }

    func testWorkCreateCarriesMeta() {
        let store = TaskStore(inMemory: true)
        let due = ParisCalendar.startOfDay(for: Date().addingTimeInterval(3 * 86400))
        store.add([work("Finir le devis", project: "Alysea", priority: .haut, due: due)])
        let ops = store.collectPendingOps(for: .work)
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.kind, .create)
        XCTAssertEqual(ops.first?.meta, WorkMeta(project: "Alysea", priority: "haut", dueAt: due))
        // les autres canaux ne reçoivent pas la tâche Travail
        XCTAssertTrue(store.collectPendingOps(for: .braindump).isEmpty)
    }

    func testCatchUpCreateIsStampedNow() {
        let store = TaskStore(inMemory: true)
        store.add([work("Ancienne tâche Travail")])
        // add() ne date pas une tâche non synchronisée à l'époque : on simule l'état d'avant v1.2.2
        let before = Date()
        let op = store.collectPendingOps(for: .work).first
        XCTAssertNotNil(op)
        XCTAssertGreaterThanOrEqual(op!.updatedAt.timeIntervalSince1970, before.timeIntervalSince1970 - 5)
    }

    func testBraindumpOpsHaveNoMeta() {
        let store = TaskStore(inMemory: true)
        store.add([TaskRecord(text: "pain", createdAt: Date(), dueDate: Date(), localList: .braindump)])
        XCTAssertNil(store.collectPendingOps(for: .braindump).first?.meta)
    }

    func testPriorityAndClientChangesArePushed() {
        let store = TaskStore(inMemory: true)
        store.add([work("Relancer la facture")])
        let ops = store.collectPendingOps(for: .work)
        store.applyPushApplied(ops.map { AppliedResult(id: $0.id, status: "applied") })
        XCTAssertTrue(store.collectPendingOps(for: .work).isEmpty)

        let id = store.workTasks[0].id
        store.setPriority(id: id, .moyen)
        store.setProject(id: id, "Emira")
        let next = store.collectPendingOps(for: .work)
        XCTAssertEqual(next.first?.kind, .update)
        XCTAssertEqual(next.first?.meta?.priority, "moyen")
        XCTAssertEqual(next.first?.meta?.project, "Emira")
    }

    func testPullAppliesMetaToNewAndExistingTasks() throws {
        let store = TaskStore(inMemory: true)
        let id = UUID().uuidString
        let json = """
        [{"id":"\(id)","text":"Préparer le shooting","done":false,"updatedAt":"2026-10-16T08:00:00.000Z","deleted":false,
          "project":"Alysea","priority":"haut","dueAt":"2026-10-22T22:00:00.000Z"}]
        """
        store.applyPulled(try JSONDecoder().decode([WireTask].self, from: Data(json.utf8)), forList: .work)
        let t = try XCTUnwrap(store.workTasks.first)
        XCTAssertEqual(t.projectName, "Alysea")
        XCTAssertEqual(t.priority, .haut)
        XCTAssertEqual(t.dueDate, ToudouClient.parseDate("2026-10-22T22:00:00.000Z"))

        // update serveur : priorité et client effacés, plus d'échéance
        let json2 = """
        [{"id":"\(id)","text":"Préparer le shooting","done":true,"updatedAt":"2026-10-16T09:00:00.000Z","deleted":false,
          "project":null,"priority":null,"dueAt":null}]
        """
        store.applyPulled(try JSONDecoder().decode([WireTask].self, from: Data(json2.utf8)), forList: .work)
        let t2 = try XCTUnwrap(store.workTasks.first)
        XCTAssertNil(t2.projectName); XCTAssertNil(t2.priority); XCTAssertNil(t2.dueDate)
        XCTAssertTrue(t2.isDone)
    }

    func testWireWithoutMetaFieldsStillDecodes() throws {
        let json = #"[{"id":"x","text":"a","done":false,"updatedAt":"2026-10-16T08:00:00.000Z","deleted":false}]"#
        let w = try JSONDecoder().decode([WireTask].self, from: Data(json.utf8))
        XCTAssertNil(w[0].project); XCTAssertNil(w[0].dueAt)
    }

    func testMoveFromBraindumpToWorkCreatesOnTravail() {
        let store = TaskStore(inMemory: true)
        store.add([TaskRecord(text: "devis Alysea", createdAt: Date(), dueDate: Date(), localList: .braindump)])
        let id = store.thoughts[0].id
        store.dropTask(id: id, to: .work, project: "Alysea")
        let ops = store.collectPendingOps(for: .work)
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.kind, .create)
        XCTAssertEqual(ops.first?.meta?.project, "Alysea")
    }
}
