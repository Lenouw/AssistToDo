//
//  IslandController.swift
//  AssistToDo
//
//  Panneau non-activating ancré à l'encoche (top-center). Se redimensionne et se
//  repositionne selon l'état de l'îlot. Purement visuel (ne vole pas le focus).
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandController {
    private let audio: AudioCapture
    private let model: CaptureModel
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(audio: AudioCapture, model: CaptureModel) {
        self.audio = audio
        self.model = model
        // Re-layout à chaque changement d'état / d'items.
        model.$state.sink { [weak self] s in self?.layout(for: s, items: self?.model.addedItems.count ?? 0) }
            .store(in: &cancellables)
        model.$addedItems.sink { [weak self] items in
            guard let self else { return }
            self.layout(for: self.model.state, items: items.count)
        }.store(in: &cancellables)
    }

    func show() {
        if panel == nil { build() }
        layout(for: model.state, items: model.addedItems.count)
        panel?.orderFrontRegardless()   // affiche sans devenir key → focus préservé
    }

    func hide() { panel?.orderOut(nil) }

    private func build() {
        let hosting = NSHostingView(rootView: IslandView(audio: audio, model: model))
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 44),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar               // au-dessus de la barre de menus (encoche)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting
        panel = p
    }

    private func layout(for state: IslandState, items: Int) {
        guard let p = panel else { return }
        let size = Self.size(for: state, items: items)
        let vf = screenUnderCursor().frame   // frame complet → ancrage à l'encoche
        let x = vf.midX - size.width / 2
        let y = vf.maxY - size.height        // colle au bord haut
        let target = NSRect(x: x, y: y, width: size.width, height: size.height)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(target, display: true)
        }
    }

    private static func size(for state: IslandState, items: Int) -> NSSize {
        switch state {
        case .preparing, .listening, .transcribing, .error:
            return NSSize(width: 300, height: 44)
        case .result:
            return NSSize(width: 380, height: 84)
        case .added:
            return NSSize(width: 380, height: CGFloat(46 + max(1, items) * 22 + 12))
        }
    }

    private func screenUnderCursor() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
