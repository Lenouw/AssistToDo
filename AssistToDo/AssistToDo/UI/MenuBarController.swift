//
//  MenuBarController.swift
//  AssistToDo
//
//  Icône barre de menus + badge (nb tâches du jour restantes). Menu d'accès.
//

import AppKit
import Combine
import Foundation
import AssistToDoCore

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let store: TaskStore
    private let onOpenList: () -> Void
    private let onOpenSettings: () -> Void
    private var cancellable: AnyCancellable?

    init(store: TaskStore, onOpenList: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenList = onOpenList
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        cancellable = store.$badgeCount.sink { [weak self] count in
            self?.updateBadge(openCount: count)
        }
        updateBadge(openCount: store.badgeCount)
    }

    private func updateBadge(openCount: Int) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "AssistToDo")
        button.imagePosition = .imageLeading
        button.title = openCount > 0 ? " \(openCount)" : ""
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Ouvrir la liste", action: #selector(openList), keyEquivalent: "l").target = self
        menu.addItem(withTitle: "Réglages…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())

        let debug = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let debugMenu = NSMenu()
        debugMenu.addItem(withTitle: "Ajouter tâches de test", action: #selector(addTestTasks), keyEquivalent: "").target = self
        debugMenu.addItem(withTitle: "Forcer le rollover maintenant", action: #selector(forceRollover), keyEquivalent: "").target = self
        debug.submenu = debugMenu
        menu.addItem(debug)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter AssistToDo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func openList() { onOpenList() }

    @objc private func openSettings() { onOpenSettings() }

    @objc private func forceRollover() { store.forceRolloverForDebug() }

    @objc private func addTestTasks() {
        let now = Date()
        let todayStart = ParisCalendar.startOfDay(for: now)
        let yesterday = ParisCalendar.calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        store.add([
            TaskRecord(text: "Tâche du jour de test", createdAt: now, dueDate: todayStart,
                       priority: .haut, rawTranscript: "test"),
            TaskRecord(text: "Tâche d'hier (doit rouler)", createdAt: now, dueDate: yesterday,
                       rawTranscript: "test")
        ])
    }
}
