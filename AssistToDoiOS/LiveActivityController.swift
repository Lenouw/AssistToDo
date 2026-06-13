//
//  LiveActivityController.swift
//  AssistToDoiOS
//
//  Pilote la Live Activity de capture (Dynamic Island + écran verrouillé) via ActivityKit.
//  Démarrage au premier plan sur action utilisateur, mises à jour locales (pas de push APNs),
//  fin à la sauvegarde. Sans Dynamic Island, le système rend l'activité sur l'écran verrouillé.
//

import Foundation
import ActivityKit

@MainActor
final class LiveActivityController {
    private var activity: Activity<CaptureActivityAttributes>?

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Une seule activité à la fois.
        if activity != nil { return }
        let state = CaptureActivityAttributes.ContentState(phase: .listening, detail: "À l'écoute")
        do {
            activity = try Activity.request(
                attributes: CaptureActivityAttributes(),
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Live Activity non démarrée : \(error)")
        }
    }

    func update(phase: CaptureActivityAttributes.Phase, detail: String) {
        guard let activity else { return }
        let state = CaptureActivityAttributes.ContentState(phase: phase, detail: detail)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end(phase: CaptureActivityAttributes.Phase, detail: String) {
        guard let activity else { return }
        let state = CaptureActivityAttributes.ContentState(phase: phase, detail: detail)
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 2))
        }
        self.activity = nil
    }
}
