import Foundation

public struct TaskRecord: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var dueDate: Date?
    public var remindAt: Date?
    public var notify: Bool
    public var notificationId: String?
    public var priority: Priority?
    public var tags: [String]
    public var isDone: Bool
    public var doneAt: Date?
    public var rolloverCount: Int
    public var rawTranscript: String
    public var parseStatus: ParseStatus
    /// Où vit la tâche : liste locale, Rappels Apple, Calendrier Apple, Notes.
    public var destination: Destination
    /// Identifiant Apple (EKReminder.calendarItemIdentifier / EKEvent.eventIdentifier) si applicable.
    public var externalId: String?
    /// Ordre manuel dans sa section (plus petit = plus haut).
    public var orderIndex: Int
    /// Sous-liste si destination == .local : vidage de cerveau (défaut) ou code (Claude Code).
    public var localList: LocalList

    public enum ParseStatus: String, Codable, Sendable { case parsed, rawOnly, pending }

    public init(id: UUID = UUID(), text: String, createdAt: Date, dueDate: Date? = nil,
                remindAt: Date? = nil, notify: Bool = false, notificationId: String? = nil,
                priority: Priority? = nil, tags: [String] = [], isDone: Bool = false,
                doneAt: Date? = nil, rolloverCount: Int = 0, rawTranscript: String = "",
                parseStatus: ParseStatus = .parsed, destination: Destination = .local,
                externalId: String? = nil, orderIndex: Int = 0, localList: LocalList = .braindump) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.dueDate = dueDate
        self.remindAt = remindAt; self.notify = notify; self.notificationId = notificationId
        self.priority = priority; self.tags = tags; self.isDone = isDone; self.doneAt = doneAt
        self.rolloverCount = rolloverCount; self.rawTranscript = rawTranscript; self.parseStatus = parseStatus
        self.destination = destination; self.externalId = externalId; self.orderIndex = orderIndex
        self.localList = localList
    }
}
