import Foundation

/// Destination d'une capture : liste locale, app Rappels Apple, ou Calendrier Apple.
public enum Destination: String, Codable, Sendable {
    case local, reminders, calendar
}

public struct ParsedTask: Equatable, Sendable {
    public var text: String
    public var destination: Destination
    public var remindAtRaw: String?
    public var dueDateRaw: String?
    public var durationMinutes: Int?
    public var listName: String?       // liste Rappels cible
    public var calendarName: String?   // calendrier cible
    public var priority: Priority?
    public var notify: Bool
    public var tags: [String]

    public init(text: String, destination: Destination = .local,
                remindAtRaw: String? = nil, dueDateRaw: String? = nil,
                durationMinutes: Int? = nil, listName: String? = nil, calendarName: String? = nil,
                priority: Priority? = nil, notify: Bool = false, tags: [String] = []) {
        self.text = text; self.destination = destination
        self.remindAtRaw = remindAtRaw; self.dueDateRaw = dueDateRaw
        self.durationMinutes = durationMinutes; self.listName = listName; self.calendarName = calendarName
        self.priority = priority; self.notify = notify; self.tags = tags
    }
}
