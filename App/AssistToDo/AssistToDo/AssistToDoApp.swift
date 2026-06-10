//
//  AssistToDoApp.swift
//  AssistToDo
//

import SwiftUI

@main
struct AssistToDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // App menu-bar : pas de fenêtre principale. La scène Settings reste vide pour l'instant.
        Settings {
            EmptyView()
        }
    }
}
