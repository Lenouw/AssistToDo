import XCTest
@testable import AssistToDoKit
@testable import AssistToDoCore

/// Panneau Travail : routage par mot-clé, client, tri par priorité, pas de sync Toudou.
final class WorkPanelTests: XCTestCase {
    private func parse(_ json: String, _ transcript: String = "Travail : envoyer le devis à Alysea") async -> [RoutedTask] {
        await TaskParser(client: TaskParserEchoTests.ScriptedClient([json])).parse(transcript: transcript, now: Date())
    }

    func test_workTodo_range_dans_travail_avec_client() async {
        let out = await parse(#"{"tasks":[{"text":"Envoyer le devis","destination":"local","workTodo":true,"projectName":"Alysea","priority":"haut"}]}"#)
        XCTAssertEqual(out.first?.record.localList, .work)
        XCTAssertEqual(out.first?.record.projectName, "Alysea")
        XCTAssertEqual(out.first?.record.priority, .haut)
    }

    func test_code_gagne_sur_travail() async {
        let out = await parse(#"{"tasks":[{"text":"Ajouter le dark mode","destination":"local","codeTodo":true,"workTodo":true}]}"#)
        XCTAssertEqual(out.first?.record.localList, .code)
    }

    func test_client_absent_reste_nil() async {
        let out = await parse(#"{"tasks":[{"text":"Faire la compta","destination":"local","workTodo":true,"projectName":null}]}"#)
        XCTAssertEqual(out.first?.record.localList, .work)
        XCTAssertNil(out.first?.record.projectName)
    }

    @MainActor func test_tri_priorite_puis_echeance() throws {
        let store = TaskStore(inMemory: true)
        let d1 = Date(timeIntervalSinceNow: 86400), d2 = Date(timeIntervalSinceNow: 3 * 86400)
        store.add([
            TaskRecord(text: "bas", createdAt: Date(), priority: .bas, localList: .work),
            TaskRecord(text: "sans", createdAt: Date(), localList: .work),
            TaskRecord(text: "haut-tard", createdAt: Date(), dueDate: d2, priority: .haut, localList: .work),
            TaskRecord(text: "haut-tot", createdAt: Date(), dueDate: d1, priority: .haut, localList: .work),
            TaskRecord(text: "moyen", createdAt: Date(), priority: .moyen, localList: .work),
        ])
        XCTAssertEqual(store.workTasks.map(\.text), ["haut-tot", "haut-tard", "moyen", "sans", "bas"])
    }

    @MainActor func test_travail_ne_part_pas_sur_toudou_et_clients_connus() {
        let store = TaskStore(inMemory: true)
        store.add([TaskRecord(text: "A", createdAt: Date(), localList: .work, projectName: "Zeta"),
                   TaskRecord(text: "B", createdAt: Date(), localList: .work, projectName: "Alysea")])
        XCTAssertTrue(store.collectPendingOps(for: .work).isEmpty)   // aucune op Toudou
        XCTAssertEqual(store.knownProjects, ["Alysea", "Zeta"])
    }

    @MainActor func test_deplacement_vers_travail_garde_le_client_et_setters() throws {
        let store = TaskStore(inMemory: true)
        store.add([TaskRecord(text: "Retoucher les photos", createdAt: Date(), localList: .braindump)])
        let id = try XCTUnwrap(store.thoughts.first?.id)
        store.moveToList(id: id, to: .work)
        let w = try XCTUnwrap(store.workTasks.first)
        XCTAssertTrue(store.thoughts.isEmpty)
        store.setProject(id: w.id, "  Alysea ")
        store.setPriority(id: w.id, .haut)
        XCTAssertEqual(store.workTasks.first?.projectName, "Alysea")
        XCTAssertEqual(store.workTasks.first?.priority, .haut)
        store.setProject(id: w.id, "")
        XCTAssertNil(store.workTasks.first?.projectName)
    }
}

/// Glisser-déposer entre panneaux.
final class WorkDropTests: XCTestCase {
    @MainActor func test_deposer_du_vidage_sur_un_groupe_client() throws {
        let store = TaskStore(inMemory: true)
        store.add([TaskRecord(text: "Retoucher", createdAt: Date(), localList: .braindump)])
        let id = try XCTUnwrap(store.thoughts.first?.id)
        store.dropTask(id: id, to: .work, project: "Alysea")
        XCTAssertTrue(store.thoughts.isEmpty)
        XCTAssertEqual(store.workTasks.first?.projectName, "Alysea")
    }

    @MainActor func test_deposer_dans_travail_entre_deux_clients_change_juste_le_client() throws {
        let store = TaskStore(inMemory: true)
        store.add([TaskRecord(text: "Devis", createdAt: Date(), localList: .work, projectName: "Alysea")])
        let id = try XCTUnwrap(store.workTasks.first?.id)
        XCTAssertEqual(store.dropTask(id: id, to: .work, project: "ARP 2000"), id)   // même id, pas de copie
        XCTAssertEqual(store.workTasks.count, 1)
        XCTAssertEqual(store.workTasks.first?.projectName, "ARP 2000")
    }

    @MainActor func test_deposer_de_travail_vers_le_vidage() throws {
        let store = TaskStore(inMemory: true)
        store.add([TaskRecord(text: "Idée", createdAt: Date(), localList: .work, projectName: "Alysea")])
        let id = try XCTUnwrap(store.workTasks.first?.id)
        store.dropTask(id: id, to: .braindump)
        XCTAssertTrue(store.workTasks.isEmpty)
        XCTAssertEqual(store.thoughts.first?.text, "Idée")
    }
}
