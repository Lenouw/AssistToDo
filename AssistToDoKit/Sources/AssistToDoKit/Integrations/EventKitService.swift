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
import AssistToDoCore

/// Ligne d'agenda du jour (lecture seule) affichée en bas du panneau.
public struct TodayItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let date: Date?      // début (event) ou échéance (rappel) ; nil = journée entière
    public let isEvent: Bool    // true = Calendrier, false = Rappel
    public let subtitle: String?  // nom de la liste / calendrier Apple

    public init(id: String, title: String, date: Date?, isEvent: Bool, subtitle: String? = nil) {
        self.id = id; self.title = title; self.date = date; self.isEvent = isEvent; self.subtitle = subtitle
    }
}

public final class EventKitService {
    public static let shared = EventKitService()
    private let store = EKEventStore()

    public enum RoutingError: Error { case accessDenied, noReminderList, noCalendar, noEventIdentifier }

    // Noms en cache (rafraîchis quand l'accès est accordé). Lus par le prompt + les Réglages.
    public private(set) var calendarTitles: [String] = []
    public private(set) var reminderListTitles: [String] = []

    // MARK: - Accès

    public var hasCalendarAccess: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .fullAccess || s == .writeOnly
    }
    public var hasRemindersAccess: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    public func ensureRemindersAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return true
        case .notDetermined:
            let ok = try await store.requestFullAccessToReminders()
            if ok { refreshReminderLists() }
            return ok
        default: return false
        }
    }

    public func ensureCalendarAccess() async throws -> Bool {
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
    public func refreshCachedNames() {
        if hasCalendarAccess { refreshCalendars() }
        if hasRemindersAccess { refreshReminderLists() }
    }

    private func refreshCalendars() {
        calendarTitles = Self.uniqued(store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { $0.title })
    }
    private func refreshReminderLists() {
        reminderListTitles = Self.uniqued(store.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
            .map { $0.title })
    }

    /// Dédoublonne en gardant l'ordre (deux agendas de même nom → un seul dans les pickers).
    private static func uniqued(_ arr: [String]) -> [String] {
        var seen = Set<String>()
        return arr.filter { seen.insert($0).inserted }
    }

    // MARK: - Création

    /// Crée le rappel et retourne son identifiant (pour le miroir local).
    @discardableResult
    public func createReminder(title: String, due: Date?, listName: String?, defaultListName: String?) async throws -> String {
        guard try await ensureRemindersAccess() else { throw RoutingError.accessDenied }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = pickReminderList(named: listName ?? defaultListName)
        guard reminder.calendar != nil else { throw RoutingError.noReminderList }

        if let due {
            var comps = ParisCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            comps.calendar = ParisCalendar.calendar
            comps.timeZone = ParisCalendar.tz
            reminder.dueDateComponents = comps
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    /// Crée l'événement et retourne son identifiant.
    @discardableResult
    public func createEvent(title: String, start: Date, durationMinutes: Int, allDay: Bool,
                     calendarName: String?, defaultCalendarName: String?,
                     alarmOffsets: [TimeInterval]) async throws -> String {
        guard try await ensureCalendarAccess() else { throw RoutingError.accessDenied }

        let event = EKEvent(eventStore: store)
        event.title = title
        if allDay {
            event.isAllDay = true
            event.startDate = start
            event.endDate = start
        } else {
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        }
        guard let cal = pickEventCalendar(named: calendarName ?? defaultCalendarName) else {
            throw RoutingError.noCalendar
        }
        event.calendar = cal
        for offset in alarmOffsets {
            event.addAlarm(EKAlarm(relativeOffset: offset))   // offset négatif = avant le début
        }
        try store.save(event, span: .thisEvent, commit: true)
        // eventIdentifier peut être nil sur certains calendriers iCloud tant que l'event n'est pas
        // committé : sans id, l'app ne pourrait plus jamais supprimer/modifier l'event (orphelin).
        guard let id = event.eventIdentifier else { throw RoutingError.noEventIdentifier }
        return id
    }

    // MARK: - Lecture de l'agenda du jour (zone du bas, lecture seule)

    /// Événements du jour (Paris). Vide si accès lecture non accordé (writeOnly ne lit pas).
    public func fetchTodayEvents() -> [TodayItem] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let start = ParisCalendar.startOfDay(for: Date())
        guard let end = ParisCalendar.calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred)
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }   // journée entière en premier
                return lhs.startDate < rhs.startDate
            }
            .map { TodayItem(id: $0.eventIdentifier ?? UUID().uuidString,
                             title: $0.title ?? "Sans titre",
                             date: $0.isAllDay ? nil : $0.startDate,
                             isEvent: true, subtitle: $0.calendar?.title) }
    }

    /// Rappels Apple dus aujourd'hui (Paris), non complétés. Vide si accès non accordé.
    public func fetchTodayReminders() async -> [TodayItem] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        let lists = store.calendars(for: .reminder)
        let pred = store.predicateForReminders(in: lists)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
        let start = ParisCalendar.startOfDay(for: Date())
        guard let end = ParisCalendar.calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return reminders
            .filter { !$0.isCompleted }
            .compactMap { r -> TodayItem? in
                guard let comps = r.dueDateComponents,
                      let due = ParisCalendar.calendar.date(from: comps),
                      due >= start, due < end else { return nil }
                return TodayItem(id: r.calendarItemIdentifier, title: r.title ?? "", date: due, isEvent: false, subtitle: r.calendar?.title)
            }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// Rappels Apple OUVERTS (non complétés) à traiter dans l'app : échéance aujourd'hui, EN RETARD,
    /// ou sans date. Les rappels futurs (demain+) sont exclus (pas encore actifs). iCloud reste la
    /// source ; l'app les fait juste « rouler » jusqu'à validation, sans modifier leur date.
    public func fetchOpenReminders() async -> [TodayItem] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        let lists = store.calendars(for: .reminder)
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
        let cal = ParisCalendar.calendar
        guard let endToday = cal.date(byAdding: .day, value: 1, to: ParisCalendar.startOfDay(for: Date())) else { return [] }
        return reminders
            .filter { !$0.isCompleted }
            .compactMap { r -> TodayItem? in
                let due = r.dueDateComponents.flatMap { cal.date(from: $0) }
                if let due, due >= endToday { return nil }   // échéance future → pas encore active
                return TodayItem(id: r.calendarItemIdentifier, title: r.title ?? "", date: due, isEvent: false, subtitle: r.calendar?.title)
            }
            // En retard / dus en premier (date la plus ancienne en haut), sans date à la fin.
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Marque comme faits TOUS les rappels iCloud ouverts « actifs » (échéance passée/aujourd'hui ou
    /// sans date). Ne touche PAS les rappels datés dans le futur. Renvoie le nombre validé.
    @discardableResult
    public func completeAllOpenReminders() async -> Int {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return 0 }
        let lists = store.calendars(for: .reminder)
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
        let cal = ParisCalendar.calendar
        guard let endToday = cal.date(byAdding: .day, value: 1, to: ParisCalendar.startOfDay(for: Date())) else { return 0 }
        var n = 0
        for r in reminders where !r.isCompleted {
            let due = r.dueDateComponents.flatMap { cal.date(from: $0) }
            if let due, due >= endToday { continue }   // garde les rappels futurs intacts
            r.isCompleted = true
            try? store.save(r, commit: false)
            n += 1
        }
        try? store.commit()
        return n
    }

    // MARK: - Modification d'items existants (depuis le panneau)

    /// Marque un rappel Apple comme complété/non complété.
    public func setReminderCompleted(id: String, completed: Bool) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = completed
        try? store.save(reminder, commit: true)
    }

    public func deleteReminder(id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try? store.remove(reminder, commit: true)
    }

    /// Décale un rappel à DEMAIN (même heure si une heure est posée), Europe/Paris.
    public func postponeReminderToTomorrow(id: String) {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        let cal = ParisCalendar.calendar
        let base = r.dueDateComponents.flatMap { cal.date(from: $0) } ?? Date()
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: base) else { return }
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: tomorrow)
        comps.calendar = cal
        comps.timeZone = ParisCalendar.tz
        r.dueDateComponents = comps
        // Recale l'alarme absolue sur la nouvelle échéance si une alarme existait.
        if let alarms = r.alarms, !alarms.isEmpty {
            alarms.forEach { r.removeAlarm($0) }
            r.addAlarm(EKAlarm(absoluteDate: tomorrow))
        }
        try? store.save(r, commit: true)
    }

    public func deleteEvent(id: String) {
        guard let event = store.event(withIdentifier: id) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    /// État de complétion live d'un rappel (nil si introuvable).
    public func isReminderCompleted(id: String) -> Bool? {
        (store.calendarItem(withIdentifier: id) as? EKReminder)?.isCompleted
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
