//
//  EventKitService.swift
//  AssistToDo
//
//  Écrit dans Rappels Apple (EKReminder) et Calendrier Apple (EKEvent).
//  Permissions demandées à la première tâche routée (pas à l'onboarding).
//  Toute erreur remonte à l'appelant qui retombe en local : capture jamais perdue.
//

import Foundation
import EventKit

final class EventKitService {
    // Une seule instance : l'init de EKEventStore ouvre une connexion XPC (coûteuse).
    static let shared = EventKitService()
    private let store = EKEventStore()

    enum RoutingError: Error {
        case accessDenied
        case noReminderList
        case noCalendar
    }

    // MARK: - Accès

    func ensureRemindersAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return true
        case .notDetermined: return try await store.requestFullAccessToReminders()
        default: return false
        }
    }

    func ensureCalendarAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly: return true
        case .notDetermined: return try await store.requestFullAccessToEvents()
        default: return false
        }
    }

    // MARK: - Création

    /// Crée un rappel dans l'app Rappels. `listName` cible une liste précise si elle existe.
    func createReminder(title: String, due: Date?, listName: String?) async throws {
        guard try await ensureRemindersAccess() else { throw RoutingError.accessDenied }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title

        let calendars = store.calendars(for: .reminder)
        reminder.calendar = listName.flatMap { name in
            calendars.first { $0.title.caseInsensitiveCompare(name) == .orderedSame }
        }
        ?? store.defaultCalendarForNewReminders()
        ?? calendars.first { $0.allowsContentModifications }

        guard reminder.calendar != nil else { throw RoutingError.noReminderList }

        if let due {
            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            comps.calendar = Calendar.current
            reminder.dueDateComponents = comps
            // L'alarme garantit la notification système (comme le fait l'app Rappels).
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
    }

    /// Crée un événement dans le Calendrier (alarme 10 min avant).
    func createEvent(title: String, start: Date, durationMinutes: Int) async throws {
        guard try await ensureCalendarAccess() else { throw RoutingError.accessDenied }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        guard let cal = store.defaultCalendarForNewEvents else { throw RoutingError.noCalendar }
        event.calendar = cal
        event.addAlarm(EKAlarm(relativeOffset: -600))
        try store.save(event, span: .thisEvent, commit: true)
    }
}
