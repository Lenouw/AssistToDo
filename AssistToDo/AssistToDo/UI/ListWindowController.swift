//
//  ListWindowController.swift
//  AssistToDo
//
//  Panneau colonne (droite de l'écran) à deux modes : liste des tâches, ou Réglages
//  affichés DANS le même panneau (pas de fenêtre séparée). Auto-fermeture au clic
//  ailleurs ou sur Échap.
//

import AppKit
import SwiftUI

/// Panneau qui peut devenir key (pour cocher/éditer) et se ferme sur Échap.
final class AutoDismissPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) } // Échap = fermer
}

enum PanelMode {
    case list, settings
}

@MainActor
final class PanelModeModel: ObservableObject {
    @Published var mode: PanelMode = .list
}

/// Contenu du panneau : bascule liste ↔ réglages dans la même fenêtre.
struct PanelRootView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var modeModel: PanelModeModel

    var body: some View {
        switch modeModel.mode {
        case .list:
            ListView(store: store, onOpenSettings: { modeModel.mode = .settings })
        case .settings:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        modeModel.mode = .list
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retour à la liste")
                    Text("Réglages").font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)

                SettingsView()
            }
        }
    }
}

@MainActor
final class ListWindowController: NSObject, NSWindowDelegate {
    private let store: TaskStore
    private let modeModel = PanelModeModel()
    private var panel: AutoDismissPanel?
    private let width: CGFloat = 340

    init(store: TaskStore) {
        self.store = store
        super.init()
    }

    func show() {
        modeModel.mode = .list
        present()
    }

    func showSettings() {
        modeModel.mode = .settings
        present()
    }

    private func present() {
        if panel == nil { build() }
        guard let p = panel else { return }
        if p.isKeyWindow { return }   // déjà visible : juste changer de mode, pas de re-animation
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
        let hosting = NSHostingController(rootView: PanelRootView(store: store, modeModel: modeModel))
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
