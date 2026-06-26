//
//  NotificationManager.swift
//  AssistToDoKit
//
//  Rappels locaux interactifs : boutons de report (5/10/15/30 min, demain) + Fait.
//

import Foundation
import UserNotifications
import AssistToDoCore

public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let categoryId = "TASK_REMINDER"

    private let store: TaskStore
    private let center = UNUserNotificationCenter.current()

    /// Ouvre la liste quand l'utilisateur tape le corps de la notif.
    public var onOpenList: () -> Void = {}

    public init(store: TaskStore) {
        self.store = store
        super.init()
        center.delegate = self
        registerCategory()
    }

    private func registerCategory() {
        func action(_ id: String, _ title: String) -> UNNotificationAction {
            UNNotificationAction(identifier: id, title: title, options: [])
        }
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [
                action("snooze5", "5 min"),
                action("snooze10", "10 min"),
                action("snooze15", "15 min"),
                action("snooze30", "30 min"),
                action("tomorrow", "À demain"),
                action("done", "Fait ✓")
            ],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - Planification

    @discardableResult
    public func schedule(for record: TaskRecord) -> String? {
        guard record.notify, let remind = record.remindAt, remind > Date() else { return nil }
        return scheduleNotification(taskId: record.id, title: record.text, at: remind)
    }

    @discardableResult
    private func scheduleNotification(taskId: UUID, title: String, at date: Date) -> String? {
        let content = UNMutableNotificationContent()
        content.title = "AssistToDo"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["taskId": taskId.uuidString]

        let comps = ParisCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = UUID().uuidString
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        return id
    }

    public func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - Nag des rappels iCloud en retard (couche in-app)

    private static let nagPrefix = "remnag-"
    private func nagIds(_ reminderId: String) -> (am: String, pm: String) {
        ("\(Self.nagPrefix)\(reminderId)-am", "\(Self.nagPrefix)\(reminderId)-pm")
    }

    /// (Re)programme 2 notifs/jour (matin + après-midi, répétées) pour CHAQUE rappel iCloud EN RETARD
    /// non fait, jusqu'à validation. iCloud notifie le jour J ; l'app prend le relais dès que dépassé.
    /// Idempotent : enlève tous les nags puis réinstalle pour l'ensemble courant des rappels en retard.
    @MainActor
    public func rescheduleReminderNags() {
        let enabled = UserDefaults.standard.object(forKey: "inappReminderNagEnabled") as? Bool ?? true
        let amMin = UserDefaults.standard.object(forKey: "inappReminderMorningMin") as? Int ?? 630   // 10:30
        let pmMin = UserDefaults.standard.object(forKey: "inappReminderAfternoonMin") as? Int ?? 930  // 15:30
        let overdue = store.openReminders.filter { item in
            guard let d = item.date else { return false }   // sans date = pas de nag
            return d < Date()
        }
        center.getPendingNotificationRequests { [weak self] reqs in
            guard let self else { return }
            let stale = reqs.map(\.identifier).filter { $0.hasPrefix(Self.nagPrefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: stale)
            guard enabled else { return }
            for item in overdue {
                let ids = self.nagIds(item.id)
                self.addDailyNag(id: ids.am, reminderId: item.id, title: item.title, hour: amMin / 60, minute: amMin % 60)
                self.addDailyNag(id: ids.pm, reminderId: item.id, title: item.title, hour: pmMin / 60, minute: pmMin % 60)
            }
        }
    }

    private func addDailyNag(id: String, reminderId: String, title: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Rappel en retard"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["reminderId": reminderId]
        var comps = DateComponents(); comps.hour = hour; comps.minute = minute
        comps.calendar = ParisCalendar.calendar; comps.timeZone = ParisCalendar.tz
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Délégué

    // Affiche la notif même app au premier plan.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    // Réagit aux boutons de la notif.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        let request = response.notification.request
        center.removeDeliveredNotifications(withIdentifiers: [request.identifier])

        // Nag d'un rappel iCloud : valider = fait dans iCloud, demain = repousser, sinon ouvrir.
        if let reminderId = request.content.userInfo["reminderId"] as? String {
            switch response.actionIdentifier {
            case "done":
                Task { @MainActor in await self.store.completeReminder(id: reminderId); self.rescheduleReminderNags() }
            case "tomorrow":
                Task { @MainActor in await self.store.postponeReminderToTomorrow(id: reminderId); self.rescheduleReminderNags() }
            default:
                Task { @MainActor in self.onOpenList() }
            }
            return
        }

        guard let idStr = request.content.userInfo["taskId"] as? String,
              let taskId = UUID(uuidString: idStr) else { return }
        let title = request.content.body

        switch response.actionIdentifier {
        case "snooze5":  snooze(taskId, title, minutes: 5)
        case "snooze10": snooze(taskId, title, minutes: 10)
        case "snooze15": snooze(taskId, title, minutes: 15)
        case "snooze30": snooze(taskId, title, minutes: 30)
        case "tomorrow": snoozeTomorrow(taskId, title)
        case "done":
            Task { @MainActor in self.store.markDone(id: taskId) }
        case UNNotificationDefaultActionIdentifier:
            Task { @MainActor in self.onOpenList() }
        default:
            break
        }
    }

    // MARK: - Report

    private func snooze(_ taskId: UUID, _ title: String, minutes: Int) {
        let date = Date().addingTimeInterval(Double(minutes) * 60)
        let newId = scheduleNotification(taskId: taskId, title: title, at: date)
        Task { @MainActor in self.store.updateReminder(id: taskId, remindAt: date, notificationId: newId) }
    }

    private func snoozeTomorrow(_ taskId: UUID, _ title: String) {
        // Demain 9h (Paris), pas "+24h à l'heure actuelle".
        let tomorrow = ParisCalendar.calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        guard let date = ParisCalendar.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) else { return }
        let newId = scheduleNotification(taskId: taskId, title: title, at: date)
        Task { @MainActor in self.store.updateReminder(id: taskId, remindAt: date, notificationId: newId) }
    }
}
