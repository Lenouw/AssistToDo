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
public final class TaskStore: ObservableObject {
    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// Flux des pensées vocales ancrées dans l'app (second cerveau), journal permanent.
    /// Vidage de cerveau (local braindump) + Rappels Apple, du plus récent au plus ancien.
    @Published public private(set) var thoughts: [TaskRecord] = []
    /// To-do Claude Code (local, sous-liste "code") : idées de dev / modifs clients.
    @Published public private(set) var codeTasks: [TaskRecord] = []
    /// Liste de courses in-app (local, sous-liste "shopping") : utilisée sur iOS.
    @Published public private(set) var shoppingItems: [TaskRecord] = []
    /// Agenda du jour, lecture seule, lu en direct d'iCloud.
    @Published public private(set) var todayEvents: [TodayItem] = []
    @Published public private(set) var todayReminders: [TodayItem] = []
    @Published public private(set) var badgeCount: Int = 0

    private let lastRolloverKey = "lastRolloverDay"

    // Câblés par l'app hôte (notifs locales).
    public var onCancelNotification: ((String) -> Void)?
    public var onScheduleReminder: ((TaskRecord) -> String?)?

    public convenience init() { self.init(inMemory: false) }

    /// `inMemory` : store volatile pour les tests (aucun fichier sur disque).
    init(inMemory: Bool) {
        let schema = Schema(versionedSchema: AssistToDoSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
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

    public func reload() {
        // Exclut les tombstones (supprimées localement, delete en attente de push vers Toudou).
        let all = fetchAll().filter { !$0.tombstone }.map { $0.toRecord() }
        // Vidage de cerveau : local "braindump" + Rappels Apple. (Courses/notes et events vivent chez Apple.)
        thoughts = all.filter {
            ($0.destination == .local && $0.localList == .braindump) || $0.destination == .reminders
        }.sorted(by: Self.manualOrder)
        // To-do Claude Code : local "code".
        codeTasks = all.filter { $0.destination == .local && $0.localList == .code }
            .sorted(by: Self.manualOrder)
        shoppingItems = all.filter { $0.destination == .local && $0.localList == .shopping }
            .sorted(by: Self.manualOrder)
        badgeCount = thoughts.filter { !$0.isDone }.count
    }

    /// Ordre d'affichage : ordre manuel (orderIndex croissant), à égalité le plus récent en haut.
    private static func manualOrder(_ a: TaskRecord, _ b: TaskRecord) -> Bool {
        a.orderIndex != b.orderIndex ? a.orderIndex < b.orderIndex : a.createdAt > b.createdAt
    }

    /// Réordonne (glisser) une sous-liste locale : applique l'ordre affiché. Local-only (l'ordre ne se synchronise pas).
    public func reorderLocal(orderedIds: [UUID]) {
        let byId = Dictionary(fetchAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (index, id) in orderedIds.enumerated() { byId[id]?.orderIndex = index }
        save(); reload()
    }

    /// Prochain orderIndex pour insérer EN HAUT (plus petit que tous les locaux existants).
    private func topOrderIndex() -> Int {
        (fetchAll().filter { $0.destinationRaw == "local" }.map { $0.orderIndex }.min() ?? 0) - 1
    }

    /// Synchronisable avec Toudou = to-do locale sans rappel minuté. Les deux sous-listes
    /// (braindump, code) se synchronisent, chacune vers son slug Toudou (canal dédié).
    static func isSyncable(_ e: TaskEntity) -> Bool {
        // Seules les sous-listes braindump + code se synchronisent avec Toudou.
        // La liste de courses (shopping, iOS) reste locale.
        e.destinationRaw == "local" && e.remindAt == nil
            && (e.localListRaw == "braindump" || e.localListRaw == "code")
    }

    /// Déplace une tâche locale d'une sous-liste à l'autre (vidage de cerveau ↔ code).
    /// Pour respecter la sync : on crée une nouvelle identité dans la liste cible et on retire l'ancienne
    /// (tombstone si elle était sur Toudou, sinon suppression locale).
    public func moveToList(id: UUID, to list: LocalList) {
        guard let e = fetchAll().first(where: { $0.id == id }), e.destinationRaw == "local" else { return }
        let from = LocalList(rawValue: e.localListRaw) ?? .braindump
        guard from != list else { return }

        let nextOrder = topOrderIndex()
        let copy = TaskEntity(id: UUID(), text: e.text, createdAt: e.createdAt, dueDate: e.dueDate, remindAt: nil,
                              notify: false, notificationId: nil, priorityRaw: e.priorityRaw, tags: e.tags,
                              isDone: e.isDone, doneAt: e.doneAt, rolloverCount: e.rolloverCount,
                              rawTranscript: e.rawTranscript, parseStatusRaw: e.parseStatusRaw,
                              destinationRaw: "local", externalId: nil, orderIndex: nextOrder)
        copy.localListRaw = list.rawValue
        if Self.isSyncable(copy) { copy.updatedAt = Date(); copy.syncDirty = true }  // braindump → créé sur Toudou
        context.insert(copy)

        if let nid = e.notificationId { onCancelNotification?(nid) }
        // Si la source était déjà connue de Toudou (peu importe la sous-liste), on tombstone pour
        // propager le delete sur SON slug (la tombstone garde son localListRaw). Sinon suppression dure.
        if e.remoteKnown {
            e.tombstone = true; e.syncDirty = true; e.updatedAt = Date()
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
    public func refreshToday() async {
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

    public func add(_ records: [TaskRecord]) {
        var nextTop = topOrderIndex()   // nouvelles captures insérées en haut
        for var r in records {
            if r.destination == .local { r.orderIndex = nextTop; nextTop -= 1 }
            let e = TaskEntity(record: r)
            context.insert(e)
            // Nouvelle to-do "vide-tête" → à créer sur Toudou (remoteKnown reste false → op create).
            if Self.isSyncable(e) { e.updatedAt = Date(); e.syncDirty = true }
        }
        save(); reload()
    }

    // MARK: - Cocher / supprimer (répercuté sur Apple si besoin)

    public func toggleDone(id: UUID) {
        guard let e = fetchAll().first(where: { $0.id == id }) else { return }
        e.isDone.toggle()
        e.doneAt = e.isDone ? Date() : nil
        if e.destinationRaw == "reminders", let ext = e.externalId {
            EventKitService.shared.setReminderCompleted(id: ext, completed: e.isDone)
        }
        markSyncDirty(e)
        save(); reload()
    }

    public func markDone(id: UUID) {
        guard let e = fetchAll().first(where: { $0.id == id }), !e.isDone else { return }
        e.isDone = true
        e.doneAt = Date()
        if e.destinationRaw == "reminders", let ext = e.externalId {
            EventKitService.shared.setReminderCompleted(id: ext, completed: true)
        }
        markSyncDirty(e)
        save(); reload()
    }

    public func delete(id: UUID) {
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
    public func updateReminder(id: UUID, remindAt: Date?, notificationId: String?) {
        guard let e = fetchAll().first(where: { $0.id == id }) else { return }
        e.remindAt = remindAt
        e.notify = remindAt != nil
        e.notificationId = notificationId
        if let remindAt { e.dueDate = ParisCalendar.startOfDay(for: remindAt) }
        save(); reload()
    }

    public func updateText(id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let e = fetchAll().first(where: { $0.id == id }) else { return }
        e.text = trimmed
        markSyncDirty(e)
        save(); reload()
    }

    /// Reporte une tâche locale à demain (Paris).
    public func postponeToTomorrow(id: UUID) {
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

    public func forceRolloverForDebug() {
        UserDefaults.standard.removeObject(forKey: lastRolloverKey)
        runRolloverIfNeeded()
        reload()
    }

    // MARK: - Synchronisation Toudou

    /// Dérive les ops à pousser pour UNE liste (slug Toudou). Purge au passage les tombstones
    /// jamais connues du serveur (rien à propager).
    func collectPendingOps(for list: LocalList) -> [SyncOp] {
        var ops: [SyncOp] = []
        var toDelete: [TaskEntity] = []
        for e in fetchAll() where e.syncDirty && e.localListRaw == list.rawValue {
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

    /// Applique un delta reçu de Toudou (source de vérité) au miroir local, pour une liste donnée.
    /// Renvoie `true` si le delta a bien été persisté. Le SyncCoordinator n'avance son curseur
    /// QUE dans ce cas : un save échoué ne doit pas faire sauter ces tâches au prochain pull.
    @discardableResult
    func applyPulled(_ tasks: [WireTask], forList list: LocalList) -> Bool {
        guard !tasks.isEmpty else { return true }
        let byId = Dictionary(fetchAll().map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        let today = ParisCalendar.startOfDay(for: Date())
        var nextTop = topOrderIndex()   // nouveaux miroirs Toudou insérés en haut

        for w in tasks {
            if let e = byId[w.id] {
                if w.deleted { context.delete(e); continue }
                // On accepte le serveur sauf si un changement local non encore poussé est plus récent.
                // Strictement `>` : à timestamp ÉGAL, l'édition locale dirty (pas encore poussée) gagne,
                // sinon un écho serveur à la même seconde écraserait la modif que l'on s'apprête à pousser.
                if !e.syncDirty || w.updatedAt > e.updatedAt {
                    e.text = w.text
                    e.isDone = w.done
                    e.doneAt = w.done ? (e.doneAt ?? Date()) : nil
                    e.localListRaw = list.rawValue   // la version serveur fait foi sur la sous-liste
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
                                   destinationRaw: "local", externalId: nil, orderIndex: nextTop)
                e.localListRaw = list.rawValue   // place le miroir dans la bonne sous-liste (braindump/code)
                e.updatedAt = w.updatedAt
                e.remoteKnown = true
                e.syncDirty = false
                context.insert(e)
                nextTop -= 1
            }
        }
        let ok = save(); reload(); return ok
    }

    // MARK: - Privé

    private func fetchAll() -> [TaskEntity] {
        (try? context.fetch(FetchDescriptor<TaskEntity>())) ?? []
    }

    @discardableResult
    private func save() -> Bool {
        do { try context.save(); return true } catch { print("SwiftData save error: \(error)"); return false }
    }
}
