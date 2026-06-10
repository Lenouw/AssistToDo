//
//  HotkeyManager.swift
//  AssistToDo
//
//  Raccourci global push-to-talk. keyDown = début, keyUp = fin.
//  Défaut ⌃⌥Espace, rebindable via les Réglages (KeyboardShortcuts.Recorder).
//

import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let capture = Self("capture", default: .init(.space, modifiers: [.control, .option]))
}

@MainActor
final class HotkeyManager {
    /// Appelé quand on commence à maintenir le raccourci.
    var onPressStart: () -> Void = {}
    /// Appelé quand on relâche le raccourci.
    var onPressEnd: () -> Void = {}

    init() {
        KeyboardShortcuts.onKeyDown(for: .capture) { [weak self] in self?.onPressStart() }
        KeyboardShortcuts.onKeyUp(for: .capture) { [weak self] in self?.onPressEnd() }
    }
}
