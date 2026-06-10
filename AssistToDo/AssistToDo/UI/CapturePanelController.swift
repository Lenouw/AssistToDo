//
//  CapturePanelController.swift
//  AssistToDo
//
//  Panneau HUD non-activating : apparaît au centre sans voler le focus de l'app active.
//  Purement visuel (ignoresMouseEvents) → ne gêne jamais ce que tu fais.
//

import AppKit
import SwiftUI

@MainActor
final class CapturePanelController {
    private let audio: AudioCapture
    private let model: CaptureModel
    private var panel: NSPanel?
    private let size = NSSize(width: 260, height: 120)

    init(audio: AudioCapture, model: CaptureModel) {
        self.audio = audio
        self.model = model
    }

    func show() {
        if panel == nil { build() }
        positionCenter()
        panel?.orderFrontRegardless()   // affiche sans devenir key → focus préservé
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func build() {
        let hosting = NSHostingView(rootView: HUDView(audio: audio, model: model))
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true       // HUD visuel : laisse passer les clics
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting
        panel = p
    }

    private func positionCenter() {
        guard let p = panel else { return }
        let vf = screenUnderCursor().visibleFrame
        let x = vf.midX - size.width / 2
        let y = vf.midY - size.height / 2
        p.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func screenUnderCursor() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
