//
//  TaskEntity.swift
//  AssistToDo
//
//  Modèle SwiftData, miroir persistant de TaskRecord (struct métier du package cœur).
//

import Foundation
import SwiftData
import AssistToDoCore

/// Schéma versionné dès v1 pour permettre des migrations futures sans corruption.
enum AssistToDoSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [TaskEntity.self] }
}

@Model
final class TaskEntity {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date
    var dueDate: Date?
    var remindAt: Date?
    var notify: Bool
    var notificationId: String?
    var priorityRaw: String?
    var tags: [String]
    var isDone: Bool
    var doneAt: Date?
    var rolloverCount: Int
    var rawTranscript: String
    var parseStatusRaw: String
    // Valeurs par défaut → migration légère SwiftData automatique pour les anciens stores.
    var destinationRaw: String = "local"
    var externalId: String?
    var orderIndex: Int = 0

    init(id: UUID, text: String, createdAt: Date, dueDate: Date?, remindAt: Date?,
         notify: Bool, notificationId: String?, priorityRaw: String?, tags: [String],
         isDone: Bool, doneAt: Date?, rolloverCount: Int, rawTranscript: String,
         parseStatusRaw: String, destinationRaw: String = "local",
         externalId: String? = nil, orderIndex: Int = 0) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.dueDate = dueDate
        self.remindAt = remindAt; self.notify = notify; self.notificationId = notificationId
        self.priorityRaw = priorityRaw; self.tags = tags; self.isDone = isDone; self.doneAt = doneAt
        self.rolloverCount = rolloverCount; self.rawTranscript = rawTranscript; self.parseStatusRaw = parseStatusRaw
        self.destinationRaw = destinationRaw; self.externalId = externalId; self.orderIndex = orderIndex
    }
}

extension TaskEntity {
    convenience init(record r: TaskRecord) {
        self.init(id: r.id, text: r.text, createdAt: r.createdAt, dueDate: r.dueDate,
                  remindAt: r.remindAt, notify: r.notify, notificationId: r.notificationId,
                  priorityRaw: r.priority?.rawValue, tags: r.tags, isDone: r.isDone,
                  doneAt: r.doneAt, rolloverCount: r.rolloverCount, rawTranscript: r.rawTranscript,
                  parseStatusRaw: r.parseStatus.rawValue, destinationRaw: r.destination.rawValue,
                  externalId: r.externalId, orderIndex: r.orderIndex)
    }

    func toRecord() -> TaskRecord {
        TaskRecord(id: id, text: text, createdAt: createdAt, dueDate: dueDate, remindAt: remindAt,
                   notify: notify, notificationId: notificationId,
                   priority: priorityRaw.flatMap(Priority.init(rawValue:)), tags: tags,
                   isDone: isDone, doneAt: doneAt, rolloverCount: rolloverCount,
                   rawTranscript: rawTranscript,
                   parseStatus: TaskRecord.ParseStatus(rawValue: parseStatusRaw) ?? .parsed,
                   destination: Destination(rawValue: destinationRaw) ?? .local,
                   externalId: externalId, orderIndex: orderIndex)
    }

    /// Met à jour l'entité existante depuis un record (utilisé par le rollover).
    func apply(_ r: TaskRecord) {
        text = r.text; dueDate = r.dueDate; remindAt = r.remindAt; notify = r.notify
        notificationId = r.notificationId; priorityRaw = r.priority?.rawValue; tags = r.tags
        isDone = r.isDone; doneAt = r.doneAt; rolloverCount = r.rolloverCount
        rawTranscript = r.rawTranscript; parseStatusRaw = r.parseStatus.rawValue
        destinationRaw = r.destination.rawValue; externalId = r.externalId; orderIndex = r.orderIndex
    }
}
