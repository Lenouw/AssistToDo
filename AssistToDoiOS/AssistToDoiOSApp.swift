//
//  AssistToDoiOSApp.swift
//  AssistToDoiOS
//
//  Point d'entrée de l'app iPhone.
//

import SwiftUI
import AssistToDoKit

@main
struct AssistToDoiOSApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.capture)
                .tint(.atdAccent)                     // identité Studio nuit
                .preferredColorScheme(.dark)          // dark verrouillé (direction B)
                .task { await model.requestNotifications() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:     model.onForeground()
            case .background: model.onBackground()
            default:          break
            }
        }
    }
}
