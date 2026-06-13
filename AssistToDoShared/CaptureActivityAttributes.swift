//
//  CaptureActivityAttributes.swift
//  Partagé entre l'app iOS et l'extension widget (Live Activity / Dynamic Island).
//
//  Décrit l'état de la capture vocale affiché dans la Dynamic Island (iPhone 14 Pro+)
//  et sur l'écran verrouillé (autres appareils) : écoute → traitement → ajouté.
//

import ActivityKit

public struct CaptureActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var phase: Phase
        public var detail: String   // texte court : transcript partiel ou résumé de l'ajout

        public init(phase: Phase, detail: String = "") {
            self.phase = phase
            self.detail = detail
        }
    }

    public enum Phase: String, Codable, Hashable {
        case listening    // micro actif
        case processing   // transcription + structuration LLM
        case added        // tâche rangée (succès)
        case ignored      // rien à créer
    }

    public init() {}
}
