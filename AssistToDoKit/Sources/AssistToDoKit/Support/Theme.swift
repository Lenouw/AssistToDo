//
//  Theme.swift
//  AssistToDoKit
//
//  Identité visuelle "Studio nuit" (direction B) : dark, gris chaud très foncé, accent violet
//  électrique, mono pour la liste dev. Couleurs partagées app + (à terme) widget. Thème sombre
//  verrouillé côté app pour la cohérence de l'identité.
//

import SwiftUI

public extension Color {
    /// Construit une couleur depuis un entier hexadécimal 0xRRGGBB.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    // Palette "Studio nuit". Préfixe atd pour éviter toute collision.
    static let atdBg            = Color(hex: 0x0E0E11) // fond app (presque noir chaud)
    static let atdSurface       = Color(hex: 0x17171C) // cartes
    static let atdSurfaceRaised = Color(hex: 0x1F1F26) // cartes surélevées / sheets
    static let atdInk           = Color(hex: 0xECECEF) // texte primaire
    static let atdInkSecondary  = Color(hex: 0x8A8A94) // texte secondaire
    static let atdAccent        = Color(hex: 0x6E56F7) // violet électrique (action principale)
    static let atdAccentSoft    = Color(hex: 0x6E56F7, alpha: 0.16)
    static let atdRecording     = Color(hex: 0xFF5C5C) // enregistrement en cours
    static let atdSuccess       = Color(hex: 0x3DDC97) // ajouté / fait
    static let atdHairline      = Color.white.opacity(0.08)

    // Couleurs d'identité par zone (vue dispatch).
    static let atdZoneTodo      = Color(hex: 0x6E56F7) // À faire = accent
    static let atdZoneReminders = Color(hex: 0xE0992F) // Rappels = ambre
    static let atdZoneAgenda    = Color(hex: 0x4C8DFF) // Agenda = bleu
    static let atdZoneDone      = Color(hex: 0x3DDC97) // Fait = vert signal
    static let atdCode          = Color(hex: 0x9B8CFF) // liste Claude Code (violet clair, mono)
}

#if canImport(UIKit)
import UIKit

/// Retours haptiques aux moments-clés (usage mains libres : le sensoriel remplace le visuel).
/// Limité à 3 intentions pour ne pas devenir du bruit.
public enum Haptics {
    /// Début de capture / action moyenne.
    public static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    /// Coche d'une tâche / action légère.
    public static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// Confirmation : item rangé / ajouté.
    public static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
#else
public enum Haptics {
    public static func tap() {}
    public static func light() {}
    public static func success() {}
}
#endif
