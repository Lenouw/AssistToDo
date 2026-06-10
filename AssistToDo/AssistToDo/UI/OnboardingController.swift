//
//  OnboardingController.swift
//  AssistToDo
//

import AppKit
import SwiftUI

@MainActor
final class OnboardingController {
    private var window: NSWindow?
    private let didOnboardKey = "didOnboard"

    var shouldShow: Bool { !UserDefaults.standard.bool(forKey: didOnboardKey) }

    func show() {
        let hosting = NSHostingController(rootView: OnboardingView { [weak self] in
            UserDefaults.standard.set(true, forKey: self?.didOnboardKey ?? "didOnboard")
            self?.window?.close()
        })
        let win = NSWindow(contentViewController: hosting)
        win.title = "Bienvenue"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
