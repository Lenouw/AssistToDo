//
//  TaskStore.swift
//  AssistToDo
//
//  Source unique de vérité. Stocke un miroir local de TOUTES les captures
//  (locales + Rappels Apple + Calendrier), groupées par type pour le panneau.
//  Les actions sur les items Apple (cocher/supprimer) se répercutent via EventKit.
//

import Foundation
import SwiftData
import AssistToDoCore

@MainActor
final class TaskStore: ObservableObject {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    @Published private(set) var localTasks: [TaskRecord] = []      // "Rappels rapides"
    @Published private(set) var reminderTasks: [TaskRecord] = []   // "Rappels" (Apple)
    @Published private(set) var eventTasks: [TaskRecord] = []      // "Rendez-vous" (Calendrier)
    @Published private(set) var badgeCount: Int = 0

    private let lastRolloverKey = "lastRolloverDay"

    // Câblés par l'AppDelegate (notifs locales).
    var onCancelNotification: ((String) -> Void)?
    var onScheduleReminder: ((TaskRecord) -> String?)?

    init() {
        let schema = Schema(versionedSchema: AssistToDoSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Migration impossible (ancien store incompatible) : on repart propre plutôt que crasher.
            print("Migration SwiftData échouée (\(error)), recréation du store.")
            if let url = config.url as URL? {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("store-shm"))
                try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("store-wal"))
            }
            container = (try? ModelContainer(for: schema, configurations: config))
                ?? { fatalError("Impossible de créer le store SwiftData") }()
        }
        runRolloverIfNeeded()
        reload()
    }

    // MARK: - Lecture

    func reload() {
        let all = fetchAll().map { $0.toRecord() }
        localTasks = all.filter { $0.destination == .local }.sorted(by: Self.localOrder)
        reminderTasks = all.filter { $0.destination == .reminders }.sorted(by: Self.appleOrder)
        eventTasks = all.filter { $0.destination == .calendar }.sorted(by: Self.appleOrder)
        badgeCount = localTasks.filter { !$0.isDone }.count + reminderTasks.filter { !$0.isDone }.count
    }

    // MARK: - Création

    func add(_ records: [TaskRecord]) {
        var nextOrder = (fetchAll().filter { $0.destinationRaw == "local" }.map { $0.orderIndex }.max() ?? -1) + 1
        for var r in records {
            if r.destination == .local { r.orderIndex = nextOrder; nextOrder += 1 }
            context.insert(TaskEntity(record: r))
        }
        save(); reload()
    }

    // MARK: - Cocher / supprimer (répercuté sur Apple si besoin)

    func toggleDone(id: UUID) {
        guard let e = fetchAll().first(where: { $0.id == id }) else { return }
        e.isDone.toggle()
        e.doneAt = e.isDone ? Date() : nil
        if e.destinationRaw == "reminders", let ext = e.externalId {
            EventKitService.shared.setReminderCompleted(id: ext, completed: e.isDone)
        }
        save(); reload()
    }

    func markDone(id: UUID) {
        guard let e = fetchAll().first(where: { $0.id == id }), !e.isDone else { return }
        e.isDone = true
        e.doneAt = Date()
        if e.destinationRaw == "reminders", let ext = e.externalId {
            EventKitService.shared.setReminderCompleted(id: ext, completed: true)
        }
        save(); reload()
    }

    func delete(id: UUID) {
        guard let e = fetchAll().first(where: { $0.id == id }) else { return }
        switch Destination(rawValue: e.destinationRaw) ?? .local {
        case .local:
            if let nid = e.notificationId { onCancelNotification?(nid) }
        case .reminders:
            if let ext = e.externalId { EventKitService.shared.deleteReminder(id: ext) }
        case .calendar:
            if let ext = e.externalId { EventKitService.shared.deleteEvent(id: ext) }
        case .notes:
            break
        }
        context.delete(e)
        save(); reload()
    }

    /// Met à jour le rappel d'une tâche (report depuis une notif locale). Aligne la date du jour.
    func updateReminder(id: UUID, remindAt: Date?, notificationId: String?) {
        guard let e = fetchAll().first(where: { $0.id == id }) else { return }
        e.remindAt = remindAt
        e.notify = remindAt != nil
        e.notificationId = notificationId
        if let remindAt { e.dueDate = ParisCalendar.startOfDay(for: remindAt) }
        save(); reload()
    }

    func updateText(id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let e = fetchAll().first(where: { $0.id == id }) else { return }
        e.text = trimmed
        save(); reload()
    }

    /// Réordonne les Rappels rapides (locaux) : applique le nouvel ordre affiché.
    func moveLocal(orderedIds: [UUID]) {
        let byId = Dictionary(uniqueKeysWithValues: fetchAll().map { ($0.id, $0) })
        for (index, id) in orderedIds.enumerated() {
            byId[id]?.orderIndex = index
        }
        save(); reload()
    }

    /// Reporte une tâche locale à demain (Paris).
    func postponeToTomorrow(id: UUID) {
        guard let e = fetchAll().first(where: { $0.id == id }) else { return }
        let todayStart = ParisCalendar.startOfDay(for: Date())
        e.dueDate = ParisCalendar.calendar.date(byAdding: .day, value: 1, to: todayStart)
        if let remind = e.remindAt {
            if let nid = e.notificationId { onCancelNotification?(nid) }
            let newRemind = ParisCalendar.calendar.date(byAdding: .day, value: 1, to: remind) ?? remind
            e.remindAt = newRemind
            e.notify = true
            e.notificationId = onScheduleReminder?(e.toRecord())
        }
        save(); reload()
    }

    // MARK: - Rollover idempotent (locaux uniquement)

    func runRolloverIfNeeded() {
        let localEntities = fetchAll().filter { $0.destinationRaw == "local" }
        let records = localEntities.map { $0.toRecord() }
        let last = UserDefaults.standard.string(forKey: lastRolloverKey)
        let result = RolloverEngine.apply(tasks: records, now: Date(), lastRolloverDay: last)

        let byId = Dictionary(uniqueKeysWithValues: localEntities.map { ($0.id, $0) })
        for rec in result.tasks {
            if let e = byId[rec.id], e.toRecord() != rec { e.apply(rec) }
        }
        save()
        if let day = result.rolledDay {
            UserDefaults.standard.set(day, forKey: lastRolloverKey)
        }
    }

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

    /// Locaux : ordre manuel (orderIndex), faites en dernier.
    private static func localOrder(_ a: TaskRecord, _ b: TaskRecord) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        return a.orderIndex < b.orderIndex
    }

    /// Apple : par heure (rappel / début), faites en dernier.
    private static func appleOrder(_ a: TaskRecord, _ b: TaskRecord) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        let da = a.remindAt ?? a.dueDate ?? a.createdAt
        let db = b.remindAt ?? b.dueDate ?? b.createdAt
        return da < db
    }
}
