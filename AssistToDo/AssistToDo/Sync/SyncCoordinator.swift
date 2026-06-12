//
//  SyncCoordinator.swift
//  AssistToDo
//
//  Pilote la synchro Toudou : à chaque cycle (lancement + timer ~45s + manuel),
//  push les ops locaux en attente PUIS pull le delta serveur (cf. spec §8).
//  Toudou est la source de vérité ; on n'envoie que les to-do "vide-tête".
//

import Foundation

@MainActor
final class SyncCoordinator {
    /// Référence faible pour déclencher une synchro manuelle depuis les Réglages.
    static weak var shared: SyncCoordinator?

    private let store: TaskStore
    private let client = ToudouClient()
    private var timer: Timer?
    private var syncing = false
    private let cursorKey = "toudouLastServerTime"

    init(store: TaskStore) {
        self.store = store
        SyncCoordinator.shared = self
    }

    /// (Re)démarre le cycle si l'URL + le token sont configurés. Sans config : ne fait rien.
    func start() {
        timer?.invalidate(); timer = nil
        guard client.isConfigured else { return }
        syncNow()
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Un cycle complet : push (ops en attente) puis pull (delta depuis le dernier curseur).
    func syncNow() {
        guard !syncing, client.isConfigured else { return }
        syncing = true
        Task { @MainActor in
            defer { self.syncing = false }
            do {
                // 1) Pousser les changements locaux (push avant pull, cf. spec §8).
                let ops = self.store.collectPendingOps()
                if ops.isEmpty {
                    print("Sync Toudou: rien à pousser (0 op en attente)")
                } else {
                    print("Sync Toudou: push \(ops.count) op(s) → \(ops.map { "\($0.kind.rawValue):\($0.id.prefix(8))" }.joined(separator: ", "))")
                    let res = try await self.client.push(ops)
                    print("Sync Toudou: réponse push \(res.applied.map { "\($0.id.prefix(8))=\($0.status)" }.joined(separator: ", "))")
                    self.store.applyPushApplied(res.applied)
                }
                // 2) Récupérer le delta serveur et l'appliquer au miroir local.
                let pull = try await self.client.pull(since: self.lastServerTime)
                if !pull.tasks.isEmpty { print("Sync Toudou: pull \(pull.tasks.count) tâche(s)") }
                self.store.applyPulled(pull.tasks)
                self.lastServerTime = pull.serverTime
            } catch {
                print("Sync Toudou échouée : \(error)")
            }
        }
    }

    /// Curseur de delta (dernier `serverTime` reçu), persisté en ISO 8601.
    private var lastServerTime: Date? {
        get { UserDefaults.standard.string(forKey: cursorKey).flatMap { ToudouClient.parseDate($0) } }
        set { if let v = newValue { UserDefaults.standard.set(ToudouClient.formatDate(v), forKey: cursorKey) } }
    }
}
