//
//  CaptureModel.swift
//  AssistToDo
//
//  État de l'îlot (notch) qui enchaîne écoute → transcription → ajout.
//

import SwiftUI
import AssistToDoCore

enum IslandState {
    case preparing    // micro en armement
    case listening    // écoute (ondes)
    case transcribing // traitement
    case result       // texte transcrit affiché
    case added        // confirmation "ajouté"
    case error        // rien entendu / échec
}

/// Un item ajouté, avec sa destination (pour la confirmation dans l'îlot).
struct ToastItem: Identifiable {
    let id = UUID()
    let record: TaskRecord
    let destination: Destination
    let fellBack: Bool
}

@MainActor
final class CaptureModel: ObservableObject {
    @Published var state: IslandState = .preparing
    @Published var transcript: String = ""       // texte reconnu ou message
    @Published var addedItems: [ToastItem] = []
    /// Hauteur de l'encoche : le contenu est poussé sous cette zone pour rester visible.
    @Published var topInset: CGFloat = 0
}
