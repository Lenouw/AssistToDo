//
//  ListWindowController.swift
//  AssistToDo
//
//  Panneau liste façon Copy History / Maccy : apparaît par le bas de l'écran,
//  se ferme tout seul dès qu'il perd le focus (clic ailleurs) ou sur Échap.
//

import AppKit
import SwiftUI

/// Panneau qui peut devenir key (pour cocher) et se ferme sur Échap.
final class AutoDismissPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) } // Échap = fermer
}

@MainActor
final class ListWindowController: NSObject, NSWindowDelegate {
    private let store: TaskStore
    private let onOpenSettings: () -> Void
    private var panel: AutoDismissPanel?
    private let size = NSSize(width: 360, height: 440)

    init(store: TaskStore, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    func show() {
        if panel == nil { build() }
        guard let p = panel else { return }
        let target = topFrame()
        // Démarre collé au bord haut (hors écran) puis descend en place.
        let start = NSRect(x: target.minX, y: target.maxY, width: target.width, height: target.height)
        p.setFrame(start, display: false)
        p.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(target, display: true)
            p.animator().alphaValue = 1
        }
    }

    private func build() {
        let hosting = NSHostingController(rootView: ListView(store: store, onOpenSettings: onOpenSettings))
        let p = AutoDismissPanel(contentViewController: hosting)
        p.styleMask = [.titled, .fullSizeContentView]
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.setContentSize(size)
        p.delegate = self
        panel = p
    }

    /// Position finale : en haut, centrée, juste sous la barre de menus.
    private func topFrame() -> NSRect {
        let vf = screenUnderCursor().visibleFrame
        let x = vf.midX - size.width / 2
        let y = vf.maxY - size.height - 8
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func screenUnderCursor() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // Auto-fermeture quand le panneau perd le focus (clic ailleurs).
    func windowDidResignKey(_ notification: Notification) {
        panel?.orderOut(nil)
    }
}
