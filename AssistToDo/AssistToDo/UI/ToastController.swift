//
//  ToastController.swift
//  AssistToDo
//
//  Panneau toast non-activating en haut à droite, auto-disparition après ~3s.
//  Informatif (ignoresMouseEvents) → ne vole jamais le focus.
//

import AppKit
import SwiftUI
import AssistToDoCore

@MainActor
final class ToastController {
    private let model = ToastModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private let width: CGFloat = 300

    func show(_ items: [ToastItem]) {
        guard !items.isEmpty else { return }
        model.items = items
        if panel == nil { build() }
        guard let p = panel else { return }

        let height = estimatedHeight(items.count)
        positionTopRight(height: height)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
        }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.fadeOut()
        }
    }

    private func build() {
        let hosting = NSHostingView(rootView: ToastView(model: model))
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
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
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting
        panel = p
    }

    private func fadeOut() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 0
        }, completionHandler: { [weak p] in
            p?.orderOut(nil)
        })
    }

    private func estimatedHeight(_ count: Int) -> CGFloat {
        44 + CGFloat(count) * 40 + 12
    }

    private func positionTopRight(height: CGFloat) {
        guard let p = panel else { return }
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let x = vf.maxX - width - 16
        let y = vf.maxY - height - 16
        p.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
