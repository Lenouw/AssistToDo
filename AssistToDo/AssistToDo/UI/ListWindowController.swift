//
//  ListWindowController.swift
//  AssistToDo
//
//  Panneau colonne (droite de l'écran) à deux modes : liste des tâches, ou Réglages
//  affichés DANS le même panneau (pas de fenêtre séparée). Auto-fermeture au clic
//  ailleurs ou sur Échap.
//

import AppKit
import AssistToDoKit
import SwiftUI

/// Panneau qui peut devenir key (pour cocher/éditer) et se ferme sur Échap.
final class AutoDismissPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) } // Échap = fermer
}

enum PanelMode {
    case list, settings, captures, archive
}

@MainActor
final class PanelModeModel: ObservableObject {
    @Published var mode: PanelMode = .list
}

/// Contenu du panneau : bascule liste ↔ réglages ↔ captures dans la même fenêtre.
struct PanelRootView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var modeModel: PanelModeModel
    @ObservedObject var captureStore: CaptureStore
    let processor: CaptureProcessor
    let transcriber: Transcriber

    var body: some View {
        switch modeModel.mode {
        case .list:
            ListView(store: store,
                     onOpenSettings: { modeModel.mode = .settings },
                     onOpenCaptures: { modeModel.mode = .captures },
                     onOpenArchive: { modeModel.mode = .archive })
        case .settings:
            subScreen("Réglages") { SettingsView(transcriber: transcriber) }
        case .captures:
            CapturesView(store: captureStore, processor: processor, onBack: { modeModel.mode = .list })
        case .archive:
            subScreen("Archive") { ArchiveView(store: store) }
        }
    }

    /// En-tête avec retour + contenu, pour les sous-écrans (réglages / captures).
    @ViewBuilder
    private func subScreen<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { modeModel.mode = .list } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).accessibilityLabel("Retour à la liste")
                Text(title).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 4)
            content()
        }
    }
}

@MainActor
final class ListWindowController: NSObject, NSWindowDelegate {
    private let store: TaskStore
    private let captureStore: CaptureStore
    private let processor: CaptureProcessor
    private let transcriber: Transcriber
    private let modeModel = PanelModeModel()
    private var panel: AutoDismissPanel?
    private let width: CGFloat = 340

    init(store: TaskStore, captureStore: CaptureStore, processor: CaptureProcessor, transcriber: Transcriber) {
        self.store = store
        self.captureStore = captureStore
        self.processor = processor
        self.transcriber = transcriber
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

    func showCaptures() {
        captureStore.reload()
        modeModel.mode = .captures
        present()
    }

    private func present() {
        if panel == nil { build() }
        guard let p = panel else { return }
        if p.isKeyWindow { return }   // déjà visible : juste changer de mode, pas de re-animation
        let target = rightFrame()
        // Démarre légèrement décalé à droite + transparent, puis glisse + fade en place.
        let start = NSRect(x: target.minX + 28, y: target.minY, width: target.width, height: target.height)
        p.setFrame(start, display: false)
        p.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(target, display: true)
            p.animator().alphaValue = 1
        }
    }

    /// Fade-out + slide léger vers la droite avant de masquer.
    private func dismiss() {
        guard let p = panel else { return }
        let out = NSRect(x: p.frame.minX + 28, y: p.frame.minY, width: p.frame.width, height: p.frame.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(out, display: true)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak p] in
            p?.orderOut(nil)
        })
    }

    private func build() {
        let hosting = NSHostingController(rootView: PanelRootView(store: store, modeModel: modeModel,
                                                                  captureStore: captureStore, processor: processor,
                                                                  transcriber: transcriber))
        let p = AutoDismissPanel(contentViewController: hosting)
        p.styleMask = [.titled, .fullSizeContentView]
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        // Pas de déplacement par le fond : sinon glisser un séparateur de zones déplace toute la fenêtre.
        p.isMovableByWindowBackground = false
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

    // Auto-fermeture au clic ailleurs UNIQUEMENT en mode liste.
    // En Réglages, on reste ouvert (les dialogues de permission volent le focus).
    func windowDidResignKey(_ notification: Notification) {
        if modeModel.mode == .list {
            dismiss()
        }
    }
}
