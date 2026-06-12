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
    /// Vidage de cerveau (local braindump) + Rappels Apple, du plus récent au plus ancien.
    @Published private(set) var thoughts: [TaskRecord] = []
    /// To-do Claude Code (local, sous-liste "code") : idées de dev / modifs clients.
    @Published private(set) var codeTasks: [TaskRecord] = []
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
        purgeExternalMirrors()   // nettoyage unique d'éventuels anciens miroirs calendar/notes
        runRolloverIfNeeded()
        reload()
    }

    // MARK: - Lecture

    func reload() {
        // Exclut les tombstones (supprimées localement, delete en attente de push vers Toudou).
        let all = fetchAll().filter { !$0.tombstone }.map { $0.toRecord() }
        // Vidage de cerveau : local "braindump" + Rappels Apple. (Courses/notes et events vivent chez Apple.)
        thoughts = all.filter {
            ($0.destination == .local && $0.localList == .braindump) || $0.destination == .reminders
        }.sorted { $0.createdAt > $1.createdAt }
        // To-do Claude Code : local "code".
        codeTasks = all.filter { $0.destination == .local && $0.localList == .code }
            .sorted { $0.createdAt > $1.createdAt }
        badgeCount = thoughts.filter { !$0.isDone }.count
    }

    /// Synchronisable avec Toudou (liste inbox) = to-do "vide-tête" : locale, sans rappel minuté,
    /// et sous-liste "braindump". La liste "code" attend l'extension du contrat Toudou (2e liste).
    static func isSyncable(_ e: TaskEntity) -> Bool {
        e.destinationRaw == "local" && e.remindAt == nil && e.localListRaw == "braindump"
    }

    /// Déplace une tâche locale d'une sous-liste à l'autre (vidage de cerveau ↔ code).
    /// Pour respecter la sync : on crée une nouvelle identité dans la liste cible et on retire l'ancienne
    /// (tombstone si elle était sur Toudou, sinon suppression locale).
    func moveToList(id: UUID, to list: LocalList) {
        guard let e = fetchAll().first(where: { $0.id == id }), e.destinationRaw == "local" else { return }
        let from = LocalList(rawValue: e.localListRaw) ?? .braindump
        guard from != list else { return }

        let nextOrder = (fetchAll().filter { $0.destinationRaw == "local" }.map { $0.orderIndex }.max() ?? -1) + 1
        let copy = TaskEntity(id: UUID(), text: e.text, createdAt: e.createdAt, dueDate: e.dueDate, remindAt: nil,
                              notify: false, notificationId: nil, priorityRaw: e.priorityRaw, tags: e.tags,
                              isDone: e.isDone, doneAt: e.doneAt, rolloverCount: e.rolloverCount,
                              rawTranscript: e.rawTranscript, parseStatusRaw: e.parseStatusRaw,
                              destinationRaw: "local", externalId: nil, orderIndex: nextOrder)
        copy.localListRaw = list.rawValue
        if Self.isSyncable(copy) { copy.updatedAt = Date(); copy.syncDirty = true }  // braindump → créé sur Toudou
        context.insert(copy)

        if let nid = e.notificationId { onCancelNotification?(nid) }
        if from == .braindump, e.remoteKnown {
            e.tombstone = true; e.syncDirty = true; e.updatedAt = Date()   // retiré de l'inbox Toudou
        } else {
            context.delete(e)
        }
        save(); reload()
    }

    /// Marque une tâche comme modifiée à synchroniser (bump updatedAt + dirty), si elle est synchronisable.
    private func markSyncDirty(_ e: TaskEntity) {
        guard Self.isSyncable(e) else { return }
        e.updatedAt = Date()
        e.syncDirty = true
    }

    /// Recharge l'agenda du jour (Calendrier + Rappels) en direct d'iCloud, lecture seule.
    func refreshToday() async {
        let events = EventKitService.shared.fetchTodayEvents()
        let reminders = await EventKitService.shared.fetchTodayReminders()
        todayEvents = events
        todayReminders = reminders
    }

    /// Calendrier et Notes ne sont plus affichés dans l'app : on purge leurs miroirs locaux.
    /// Les items restent chez Apple (Calendrier / Notes) — on ne touche jamais l'original.
    private func purgeExternalMirrors() {
        let old = fetchAll().filter { $0.destinationRaw == "calendar" || $0.destinationRaw == "notes" }
        guard !old.isEmpty else { return }
        for e in old { context.delete(e) }
        save()
    }

    // MARK: - Création

    func add(_ records: [TaskRecord]) {
        var nextOrder = (fetchAll().filter { $0.destinationRaw == "local" }.map { $0.orderIndex }.max() ?? -1) + 1
        for var r in records {
            if r.destination == .local { r.orderIndex = nextOrder; nextOrder += 1 }
            let e = TaskEntity(record: r)
            context.insert(e)
            // Nouvelle to-do "vide-tête" → à créer sur Toudou (remoteKnown reste false → op create).
            if Self.isSyncable(e) { e.updatedAt = Date(); e.syncDirty = true }
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
        markSyncDirty(e)
        save(); reload()
    }

    func markDone(id: UUID) {
        guard let e = fetchAll().first(where: { $0.id == id }), !e.isDone else { return }
        e.isDone = true
        e.doneAt = Date()
        if e.destinationRaw == "reminders", let ext = e.externalId {
            EventKitService.shared.setReminderCompleted(id: ext, completed: true)
        }
        markSyncDirty(e)
        save(); reload()
    }

    func delete(id: UUID) {
        guard let e = fetchAll().first(where: { $0.id == id }) else { return }
        // To-do synchronisable déjà connue de Toudou → tombstone (delete propagé au prochain push),
        // pas de suppression dure tant que le serveur ne l'a pas reçu.
        if Self.isSyncable(e), e.remoteKnown {
            if let nid = e.notificationId { onCancelNotification?(nid) }
            e.tombstone = true
            e.updatedAt = Date()
            e.syncDirty = true
            save(); reload()
            return
        }
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
        markSyncDirty(e)
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

    // MARK: - Synchronisation Toudou

    /// Dérive les ops à pousser depuis les tâches "dirty". Purge au passage les tombstones
    /// jamais connues du serveur (rien à propager).
    func collectPendingOps() -> [SyncOp] {
        var ops: [SyncOp] = []
        var toDelete: [TaskEntity] = []
        for e in fetchAll() where e.syncDirty {
            if e.tombstone {
                if e.remoteKnown {
                    ops.append(SyncOp(kind: .delete, id: e.id.uuidString, text: nil, done: nil, updatedAt: e.updatedAt))
                } else {
                    toDelete.append(e)   // jamais sur Toudou → suppression locale directe
                }
            } else if Self.isSyncable(e) {
                if e.remoteKnown {
                    ops.append(SyncOp(kind: .update, id: e.id.uuidString, text: e.text, done: e.isDone, updatedAt: e.updatedAt))
                } else {
                    ops.append(SyncOp(kind: .create, id: e.id.uuidString, text: e.text, done: nil, updatedAt: e.updatedAt))
                }
            }
        }
        if !toDelete.isEmpty { toDelete.forEach { context.delete($0) }; save(); reload() }
        return ops
    }

    /// Applique le résultat d'un push : op acceptée ou stale → la tâche n'est plus dirty ;
    /// un tombstone confirmé est supprimé pour de bon.
    func applyPushApplied(_ results: [AppliedResult]) {
        let byId = Dictionary(fetchAll().map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        for r in results {
            guard let e = byId[r.id] else { continue }
            if e.tombstone {
                context.delete(e)      // delete propagé (ou stale = serveur a déjà une version) → on lâche le tombstone
            } else {
                e.remoteKnown = true   // existe désormais sur Toudou (create/update appliqué ou serveur plus récent)
                e.syncDirty = false    // si stale, le pull ramènera la version serveur
            }
        }
        save(); reload()
    }

    /// Applique un delta reçu de Toudou (source de vérité) au miroir local.
    func applyPulled(_ tasks: [WireTask]) {
        guard !tasks.isEmpty else { return }
        let byId = Dictionary(fetchAll().map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        let today = ParisCalendar.startOfDay(for: Date())
        var nextOrder = (fetchAll().filter { $0.destinationRaw == "local" }.map { $0.orderIndex }.max() ?? -1) + 1

        for w in tasks {
            if let e = byId[w.id] {
                if w.deleted { context.delete(e); continue }
                // On accepte le serveur sauf si un changement local non encore poussé est plus récent.
                if !e.syncDirty || w.updatedAt >= e.updatedAt {
                    e.text = w.text
                    e.isDone = w.done
                    e.doneAt = w.done ? (e.doneAt ?? Date()) : nil
                    e.updatedAt = w.updatedAt
                    e.remoteKnown = true
                    e.syncDirty = false
                    e.tombstone = false
                }
            } else {
                if w.deleted { continue }                       // tombstone d'un id inconnu → rien
                guard let uuid = UUID(uuidString: w.id) else { continue }
                let e = TaskEntity(id: uuid, text: w.text, createdAt: Date(), dueDate: today, remindAt: nil,
                                   notify: false, notificationId: nil, priorityRaw: nil, tags: [],
                                   isDone: w.done, doneAt: w.done ? Date() : nil, rolloverCount: 0,
                                   rawTranscript: w.text, parseStatusRaw: "parsed",
                                   destinationRaw: "local", externalId: nil, orderIndex: nextOrder)
                e.updatedAt = w.updatedAt
                e.remoteKnown = true
                e.syncDirty = false
                context.insert(e)
                nextOrder += 1
            }
        }
        save(); reload()
    }

    // MARK: - Privé

    private func fetchAll() -> [TaskEntity] {
        (try? context.fetch(FetchDescriptor<TaskEntity>())) ?? []
    }

    private func save() {
        do { try context.save() } catch { print("SwiftData save error: \(error)") }
    }
}
