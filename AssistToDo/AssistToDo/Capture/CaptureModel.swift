//
//  CaptureModel.swift
//  AssistToDo
//
//  État du HUD de capture (toujours doublé en texte pour l'accessibilité).
//

import SwiftUI

enum CaptureState {
    case preparing   // micro en cours d'armement
    case listening   // prêt, en écoute
    case finishing   // relâché, traitement

    var label: String {
        switch self {
        case .preparing: return "Préparation…"
        case .listening: return "Parle, je t'écoute"
        case .finishing: return "Traitement…"
        }
    }

    var color: Color {
        switch self {
        case .preparing: return .yellow
        case .listening: return .green
        case .finishing: return .orange
        }
    }
}

@MainActor
final class CaptureModel: ObservableObject {
    @Published var state: CaptureState = .preparing
    /// Texte affiché dans le HUD (transcription ou message d'état).
    @Published var transcript: String = ""
}
