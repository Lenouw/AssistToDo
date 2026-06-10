//
//  NotificationManager.swift
//  AssistToDo
//
//  Planifie les rappels locaux à l'heure `remindAt` (Europe/Paris).
//

import Foundation
import UserNotifications
import AssistToDoCore

@MainActor
final class NotificationManager {
    /// Planifie une notif pour la tâche si elle a un rappel futur. Retourne l'id (à stocker) ou nil.
    @discardableResult
    func schedule(for record: TaskRecord) -> String? {
        guard record.notify, let remind = record.remindAt, remind > Date() else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "AssistToDo"
        content.body = record.text
        content.sound = .default

        let comps = ParisCalendar.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: remind
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
        return id
    }

    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
