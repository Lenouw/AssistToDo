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

    /// Flux des pensées vocales ancrées dans l'app (second cerveau), journal permanent.
    /// Tout sauf le calendrier (les events vivent dans le Calendrier Apple), du plus récent au plus ancien.
    @Published private(set) var thoughts: [TaskRecord] = []
    /// Agenda du jour, lecture seule, lu en direct d'iCloud.
    @Published private(set) var todayEvents: [TodayItem] = []
    @Published private(set) var todayReminders: [TodayItem] = []
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
        purgeCalendarMirrors()
        let all = fetchAll().map { $0.toRecord() }
        thoughts = all.filter { $0.destination != .calendar }
            .sorted { $0.createdAt > $1.createdAt }   // journal : plus récent en haut
        badgeCount = thoughts.filter { !$0.isDone }.count
    }

    /// Recharge l'agenda du jour (Calendrier + Rappels) en direct d'iCloud, lecture seule.
    func refreshToday() async {
        let events = EventKitService.shared.fetchTodayEvents()
        let reminders = await EventKitService.shared.fetchTodayReminders()
        todayEvents = events
        todayReminders = reminders
    }

    /// Le calendrier n'est plus affiché dans l'app : on purge les miroirs locaux d'events.
    /// L'événement reste dans le Calendrier Apple (on ne touche jamais l'EKEvent ici).
    private func purgeCalendarMirrors() {
        let old = fetchAll().filter { $0.destinationRaw == "calendar" }
        guard !old.isEmpty else { return }
        for e in old { context.delete(e) }
        save()
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
}
