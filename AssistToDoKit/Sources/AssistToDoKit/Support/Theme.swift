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

    /// Depuis une chaîne "RRGGBB" (ou "#RRGGBB") — ex. couleur d'un agenda Apple. nil si invalide.
    init?(hexString: String) {
        var s = hexString
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    // Palette "Clarté chaude" (direction C) : crème chaud, encre presque noire chaude, accent bleu
    // profond. Neutres teintés (jamais de #fff/#000 purs). La couleur sert la hiérarchie, pas l'inverse.
    static let atdBg            = Color(hex: 0xF6F3EE) // fond app (crème chaud)
    static let atdSurface       = Color(hex: 0xFCFAF6) // cartes (blanc chaud)
    static let atdSurfaceRaised = Color(hex: 0xFFFEFB) // sheets
    static let atdInk           = Color(hex: 0x2C2924) // texte primaire (presque noir chaud)
    static let atdInkSecondary  = Color(hex: 0x76716A) // texte secondaire
    static let atdInkTertiary   = Color(hex: 0x9C978F) // texte ternaire (méta discrète)
    static let atdAccent        = Color(hex: 0x2E5FCB) // bleu profond (action principale)
    static let atdAccentSoft    = Color(hex: 0x2E5FCB, alpha: 0.12)
    static let atdRecording     = Color(hex: 0xCE3B36) // enregistrement / en retard
    static let atdSuccess       = Color(hex: 0x3E9D6A) // ajouté / fait
    static let atdHairline      = Color.black.opacity(0.07)

    // Hiérarchie de priorité : hue chaude distincte de l'accent → l'importance saute aux yeux.
    static let atdPriorityHigh  = Color(hex: 0xC8512E) // priorité haute (terracotta chaud)
    static let atdPriorityMed   = Color(hex: 0xC28A2A) // priorité moyenne (ambre)

    // Couleurs d'identité par zone (vue dispatch).
    static let atdZoneTodo      = Color(hex: 0x2E5FCB) // À faire = accent
    static let atdZoneReminders = Color(hex: 0xC28A2A) // Rappels = ambre
    static let atdZoneAgenda    = Color(hex: 0x2E5FCB) // Agenda = bleu
    static let atdZoneDone      = Color(hex: 0x3E9D6A) // Fait = vert
    static let atdCode          = Color(hex: 0x6A52C8) // liste Claude Code (violet)
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
