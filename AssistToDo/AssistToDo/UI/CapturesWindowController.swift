//
//  CapturesWindowController.swift
//  AssistToDo
//
//  Fenêtre standard hébergeant l'historique des captures (filet de sécurité).
//

import AppKit
import SwiftUI
import AssistToDoKit

@MainActor
final class CapturesWindowController {
    private var window: NSWindow?
    private let store: CaptureStore
    private let processor: CaptureProcessor

    init(store: CaptureStore, processor: CaptureProcessor) {
        self.store = store
        self.processor = processor
    }

    func show() {
        store.reload()
        if window == nil {
            let hosting = NSHostingController(rootView: CapturesView(store: store, processor: processor))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Captures"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 460, height: 420))
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
