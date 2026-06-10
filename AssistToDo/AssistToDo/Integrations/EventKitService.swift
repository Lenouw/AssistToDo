//
//  EventKitService.swift
//  AssistToDo
//
//  Écrit dans Rappels Apple (EKReminder) et Calendrier Apple (EKEvent).
//  Garde en cache les noms de calendriers / listes pour les injecter au LLM
//  (routage par nom) et les proposer dans les Réglages.
//

import Foundation
import EventKit

final class EventKitService {
    static let shared = EventKitService()
    private let store = EKEventStore()

    enum RoutingError: Error { case accessDenied, noReminderList, noCalendar }

    // Noms en cache (rafraîchis quand l'accès est accordé). Lus par le prompt + les Réglages.
    private(set) var calendarTitles: [String] = []
    private(set) var reminderListTitles: [String] = []

    // MARK: - Accès

    var hasCalendarAccess: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .fullAccess || s == .writeOnly
    }
    var hasRemindersAccess: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func ensureRemindersAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return true
        case .notDetermined:
            let ok = try await store.requestFullAccessToReminders()
            if ok { refreshReminderLists() }
            return ok
        default: return false
        }
    }

    func ensureCalendarAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly: return true
        case .notDetermined:
            let ok = try await store.requestFullAccessToEvents()
            if ok { refreshCalendars() }
            return ok
        default: return false
        }
    }

    /// Rafraîchit les noms en cache si l'accès est déjà accordé (appelé au lancement).
    func refreshCachedNames() {
        if hasCalendarAccess { refreshCalendars() }
        if hasRemindersAccess { refreshReminderLists() }
    }

    private func refreshCalendars() {
        calendarTitles = store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { $0.title }
    }
    private func refreshReminderLists() {
        reminderListTitles = store.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
            .map { $0.title }
    }

    // MARK: - Création

    func createReminder(title: String, due: Date?, listName: String?, defaultListName: String?) async throws {
        guard try await ensureRemindersAccess() else { throw RoutingError.accessDenied }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = pickReminderList(named: listName ?? defaultListName)
        guard reminder.calendar != nil else { throw RoutingError.noReminderList }

        if let due {
            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            comps.calendar = Calendar.current
            reminder.dueDateComponents = comps
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
    }

    func createEvent(title: String, start: Date, durationMinutes: Int,
                     calendarName: String?, defaultCalendarName: String?) async throws {
        guard try await ensureCalendarAccess() else { throw RoutingError.accessDenied }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        guard let cal = pickEventCalendar(named: calendarName ?? defaultCalendarName) else {
            throw RoutingError.noCalendar
        }
        event.calendar = cal
        event.addAlarm(EKAlarm(relativeOffset: -600))
        try store.save(event, span: .thisEvent, commit: true)
    }

    // MARK: - Sélection (nom exact, sinon défaut système)

    private func pickEventCalendar(named name: String?) -> EKCalendar? {
        let calendars = store.calendars(for: .event).filter { $0.allowsContentModifications }
        if let name, let match = calendars.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        return store.defaultCalendarForNewEvents ?? calendars.first
    }

    private func pickReminderList(named name: String?) -> EKCalendar? {
        let lists = store.calendars(for: .reminder).filter { $0.allowsContentModifications }
        if let name, let match = lists.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        return store.defaultCalendarForNewReminders() ?? lists.first
    }
}
