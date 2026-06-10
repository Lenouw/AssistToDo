//
//  AppDelegate.swift
//  AssistToDo
//

import AppKit
import AssistToDoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App accessoire : pas d'icône Dock, vit dans la barre de menus.
        NSApp.setActivationPolicy(.accessory)

        // Preuve temporaire que le package cœur est bien lié (à retirer en Task 2.2).
        print("AssistToDoCore lié, version \(AssistToDoCore.version)")
    }
}
