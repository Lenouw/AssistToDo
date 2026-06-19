//
//  IOSTaskRouter.swift
//  AssistToDoiOS
//
//  Routage iOS d'une liste de tâches parsées vers leurs destinations (Calendrier/Rappels Apple
//  via EventKit, liste de courses in-app, liste locale). Implémente `TaskRouting` (Kit) → partagé
//  entre la capture en direct et le re-traitement (CaptureProcessor). Idempotent : supprime
//  d'abord les items précédents. Différence Mac : `.notes` (courses) → liste in-app, pas Apple Notes.
//

import Foundation
import os
import AssistToDoKit
import AssistToDoCore

private let routerLog = Logger(subsystem: "com.assisttodo", category: "Router")

/// Résultat détaillé d'un item routé (pour la confirmation de capture + le journal).
struct RoutedOutcome {
    let storedId: UUID?        // id dans TaskStore (local/reminders/courses) ; nil pour calendar
    let record: TaskRecord
    let destination: Destination
    let fellBack: Bool
}

@MainActor
final class IOSTaskRouter: TaskRouting {
    private let store: TaskStore
    private let notifications: NotificationManager

    init(store: TaskStore, notifications: NotificationManager) {
        self.store = store
        self.notifications = notifications
    }

    /// Conformité `TaskRouting` : route et retourne les ids des items locaux créés (idempotence).
    func route(_ tasks: [RoutedTask], replacing previous: [UUID]) async -> [UUID] {
        await routeDetailed(tasks, replacing: previous).compactMap { $0.storedId }
    }

    func routeDetailed(_ tasks: [RoutedTask], replacing previous: [UUID]) async -> [RoutedOutcome] {
        // Idempotence (re-traitement) : supprime les items locaux produits précédemment.
        for id in previous { store.delete(id: id) }

        let routingOn = UserDefaults.standard.object(forKey: "routingEnabled") as? Bool ?? true
        let defaultCalendar = UserDefaults.standard.string(forKey: "defaultCalendar")
        let defaultList = UserDefaults.standard.string(forKey: "defaultReminderList")

        var toStore: [TaskRecord] = []
        var outcomes: [RoutedOutcome] = []

        func keepLocal(_ rec: TaskRecord, list: LocalList = .braindump) -> TaskRecord {
            var r = rec
            r.destination = .local
            r.localList = list
            r.notificationId = notifications.schedule(for: r)
            return r
        }

        for item in tasks {
            // Routage OFF = pas de dispatch Apple (calendrier/rappels → local), MAIS la liste de
            // courses (.notes → liste in-app) reste honorée : c'est de l'app, pas du routage Apple.
            var destination = routingOn ? item.destination : (item.destination == .notes ? .notes : .local)
            // Filet : un événement sans AUCUNE date/heure dictée ne va jamais sur "aujourd'hui" inventé.
            if destination == .calendar, item.record.dueDate == nil, item.record.remindAt == nil {
                destination = .reminders
            }
            switch destination {
            case .calendar:
                do {
                    let categoryCalendar = item.calendarCategory.flatMap { cat in
                        UserDefaults.standard.string(forKey: "calendar_\(cat.rawValue)")
                    }
                    let alarmsOn = UserDefaults.standard.object(forKey: "eventAlarmsEnabled") as? Bool ?? true
                    let offsets: [TimeInterval] = alarmsOn ? [-3600, -86400] : []
                    let day = item.record.dueDate ?? Date()
                    var start = item.record.remindAt ?? day
                    var duration = item.durationMinutes ?? 60
                    var allDay = item.record.remindAt == nil
                    if item.record.remindAt == nil, item.calendarCategory == .studio {
                        let sh = UserDefaults.standard.object(forKey: "studioBlockStart") as? Int ?? 8
                        let eh = UserDefaults.standard.object(forKey: "studioBlockEnd") as? Int ?? 20
                        start = ParisCalendar.calendar.date(bySettingHour: sh, minute: 0, second: 0, of: day) ?? day
                        duration = max(60, (eh - sh) * 60)
                        allDay = false
                    }
                    let extId = try await EventKitService.shared.createEvent(
                        title: item.record.text, start: start, durationMinutes: duration, allDay: allDay,
                        calendarName: item.calendarName ?? categoryCalendar,
                        defaultCalendarName: defaultCalendar, alarmOffsets: offsets)
                    var r = item.record; r.destination = .calendar; r.externalId = extId
                    outcomes.append(RoutedOutcome(storedId: nil, record: r, destination: .calendar, fellBack: false))
                } catch {
                    routerLog.error("createEvent a échoué → fallback 'À faire'. Raison : \(String(describing: error), privacy: .public)")
                    let kept = keepLocal(item.record); toStore.append(kept)
                    outcomes.append(RoutedOutcome(storedId: kept.id, record: item.record, destination: .calendar, fellBack: true))
                }
            case .reminders:
                do {
                    let extId = try await EventKitService.shared.createReminder(
                        title: item.record.text, due: item.record.remindAt ?? item.record.dueDate,
                        listName: item.listName, defaultListName: defaultList)
                    var r = item.record; r.destination = .reminders; r.externalId = extId
                    toStore.append(r)
                    outcomes.append(RoutedOutcome(storedId: r.id, record: r, destination: .reminders, fellBack: false))
                } catch {
                    routerLog.error("createReminder a échoué → fallback 'À faire'. Raison : \(String(describing: error), privacy: .public)")
                    let kept = keepLocal(item.record); toStore.append(kept)
                    outcomes.append(RoutedOutcome(storedId: kept.id, record: item.record, destination: .reminders, fellBack: true))
                }
            case .notes:
                // iOS : pas d'Apple Notes (AppleScript indisponible) → liste de courses in-app.
                let kept = keepLocal(item.record, list: .shopping); toStore.append(kept)
                outcomes.append(RoutedOutcome(storedId: kept.id, record: item.record, destination: .notes, fellBack: false))
            case .local:
                let list: LocalList = item.record.localList == .code ? .code : .braindump
                let kept = keepLocal(item.record, list: list); toStore.append(kept)
                outcomes.append(RoutedOutcome(storedId: kept.id, record: item.record, destination: .local, fellBack: false))
            }
        }

        if !toStore.isEmpty { store.add(toStore) }
        return outcomes
    }
}
