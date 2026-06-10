//
//  TaskStore.swift
//  AssistToDo
//
//  Source unique de vérité des tâches. Toutes les mutations passent par ici,
//  puis `tasks` (publié) est rechargé → liste + badge restent synchronisés.
//

import Foundation
import SwiftData
import AssistToDoCore

@MainActor
final class TaskStore: ObservableObject {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// Tâches du jour (après rollover), triées. Pilote la liste et le badge.
    @Published private(set) var tasks: [TaskRecord] = []

    private let lastRolloverKey = "lastRolloverDay"

    init() {
        do {
            let schema = Schema(versionedSchema: AssistToDoSchemaV1.self)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Échec init SwiftData: \(error)")
        }
        runRolloverIfNeeded()
        reload()
    }

    // MARK: - Lecture

    /// Recharge `tasks` = tâches "du jour" : sans échéance, ou échéance <= aujourd'hui (Paris).
    func reload() {
        let today = ParisCalendar.ymd(for: Date())
        let all = fetchAll()
        let todays = all.filter { e in
            guard let due = e.dueDate else { return true }
            return ParisCalendar.ymd(for: due) <= today
        }
        tasks = todays.map { $0.toRecord() }.sorted(by: Self.order)
    }

    var openCount: Int { tasks.filter { !$0.isDone }.count }

    // MARK: - Mutations

    func add(_ records: [TaskRecord]) {
        for r in records { context.insert(TaskEntity(record: r)) }
        save(); reload()
    }

    func toggleDone(id: UUID) {
        guard let e = fetchAll().first(where: { $0.id == id }) else { return }
        e.isDone.toggle()
        e.doneAt = e.isDone ? Date() : nil
        save(); reload()
    }

    // MARK: - Rollover idempotent

    /// Reporte au jour courant (Paris) les tâches en retard non faites. Idempotent par jour.
    func runRolloverIfNeeded() {
        let all = fetchAll()
        let records = all.map { $0.toRecord() }
        let last = UserDefaults.standard.string(forKey: lastRolloverKey)
        let result = RolloverEngine.apply(tasks: records, now: Date(), lastRolloverDay: last)

        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        for rec in result.tasks {
            if let e = byId[rec.id], e.toRecord() != rec { e.apply(rec) }
        }
        save()
        if let day = result.rolledDay {
            UserDefaults.standard.set(day, forKey: lastRolloverKey)
        }
    }

    /// Debug : oublie le dernier jour roulé puis relance le rollover (test en session).
    func forceRolloverForDebug() {
        UserDefaults.standard.removeObject(forKey: lastRolloverKey)
        runRolloverIfNeeded()
        reload()
    }

    // MARK: - Privé

    private func fetchAll() -> [TaskEntity] {
        (try? context.fetch(FetchDescriptor<TaskEntity>())) ?? []
    }

    private func save() {
        do { try context.save() } catch { print("SwiftData save error: \(error)") }
    }

    /// Tri : non faites avant faites, puis priorité décroissante, puis heure de rappel, puis création.
    private static func order(_ a: TaskRecord, _ b: TaskRecord) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        let pa = priorityRank(a.priority), pb = priorityRank(b.priority)
        if pa != pb { return pa > pb }
        switch (a.remindAt, b.remindAt) {
        case let (x?, y?): if x != y { return x < y }
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }
        return a.createdAt < b.createdAt
    }

    private static func priorityRank(_ p: Priority?) -> Int {
        switch p { case .haut: return 3; case .moyen: return 2; case .bas: return 1; case nil: return 0 }
    }
}
