//
//  ListWindowController.swift
//  AssistToDo
//
//  Fenêtre liste (ouverte explicitement par l'utilisateur → activer/voler le focus est OK ici,
//  contrairement au HUD de capture qui restera non-activating).
//

import AppKit
import SwiftUI

@MainActor
final class ListWindowController {
    private let store: TaskStore
    private var window: NSWindow?

    init(store: TaskStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: ListView(store: store))
            let win = NSWindow(contentViewController: hosting)
            win.title = "AssistToDo"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
