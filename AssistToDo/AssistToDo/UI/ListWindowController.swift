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
    private let width: CGFloat = 340

    init(store: TaskStore, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    func show() {
        if panel == nil { build() }
        guard let p = panel else { return }
        let target = rightFrame()
        // Démarre hors écran à droite puis glisse vers l'intérieur.
        let start = NSRect(x: target.maxX, y: target.minY, width: target.width, height: target.height)
        p.setFrame(start, display: false)
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(target, display: true)
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
        p.delegate = self
        panel = p
    }

    /// Position finale : colonne verticale collée au bord droit, pleine hauteur.
    private func rightFrame() -> NSRect {
        let vf = screenUnderCursor().visibleFrame
        let x = vf.maxX - width
        let y = vf.minY
        return NSRect(x: x, y: y, width: width, height: vf.height)
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
