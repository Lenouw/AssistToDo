import Foundation

/// Destination d'une capture : liste locale, Rappels Apple, Calendrier Apple, ou Notes Apple.
public enum Destination: String, Codable, Sendable {
    case local, reminders, calendar, notes
}

/// Catégorie sémantique d'agenda (mappée à un vrai calendrier dans les Réglages).
public enum CalendarCategory: String, Codable, Sendable {
    case perso, commun, pro, studio
}

public struct ParsedTask: Equatable, Sendable {
    public var text: String
    public var destination: Destination
    public var remindAtRaw: String?
    public var dueDateRaw: String?
    public var durationMinutes: Int?
    public var listName: String?       // liste Rappels cible
    public var calendarName: String?           // calendrier cible (nom explicite dicté)
    public var calendarCategory: CalendarCategory?  // catégorie d'agenda (perso/commun/pro)
    public var noteName: String?               // note Apple cible
    public var priority: Priority?
    public var notify: Bool
    public var tags: [String]

    public init(text: String, destination: Destination = .local,
                remindAtRaw: String? = nil, dueDateRaw: String? = nil,
                durationMinutes: Int? = nil, listName: String? = nil, calendarName: String? = nil,
                calendarCategory: CalendarCategory? = nil, noteName: String? = nil,
                priority: Priority? = nil, notify: Bool = false, tags: [String] = []) {
        self.text = text; self.destination = destination
        self.remindAtRaw = remindAtRaw; self.dueDateRaw = dueDateRaw
        self.durationMinutes = durationMinutes; self.listName = listName; self.calendarName = calendarName
        self.calendarCategory = calendarCategory; self.noteName = noteName
        self.priority = priority; self.notify = notify; self.tags = tags
    }
}
