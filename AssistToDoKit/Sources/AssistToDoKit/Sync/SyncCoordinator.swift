//
//  SyncCoordinator.swift
//  AssistToDoKit
//
//  Pilote la synchro Toudou : à chaque cycle (lancement + timer ~45s + manuel),
//  push les ops locaux en attente PUIS pull le delta serveur (cf. spec §8).
//  Toudou est la source de vérité ; on n'envoie que les to-do "vide-tête".
//

import Foundation
import AssistToDoCore

@MainActor
public final class SyncCoordinator {
    /// Référence faible pour déclencher une synchro manuelle depuis les Réglages.
    public static weak var shared: SyncCoordinator?

    private let store: TaskStore
    private let client = ToudouClient()
    private var timer: Timer?
    private var syncing = false

    /// Les listes synchronisées : slug Toudou ↔ sous-liste locale.
    private let channels: [(slug: String, list: LocalList)] = [
        ("braindump", .braindump),
        ("code", .code)
    ]

    public init(store: TaskStore) {
        self.store = store
        SyncCoordinator.shared = self
    }

    /// (Re)démarre le cycle si l'URL + le token sont configurés. Sans config : ne fait rien.
    public func start() {
        timer?.invalidate(); timer = nil
        guard client.isConfigured else { return }
        syncNow()
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
    }

    public func stop() { timer?.invalidate(); timer = nil }

    /// Un cycle complet : chaque liste indépendamment (push ses ops, puis pull son delta).
    public func syncNow() {
        guard !syncing, client.isConfigured else { return }
        syncing = true
        Task { @MainActor in
            defer { self.syncing = false }
            for ch in self.channels { await self.syncList(slug: ch.slug, list: ch.list) }
        }
    }

    /// Synchronise une liste : push (ops en attente) avant pull (delta depuis son curseur dédié).
    private func syncList(slug: String, list: LocalList) async {
        do {
            let ops = store.collectPendingOps(for: list)
            if !ops.isEmpty {
                print("Sync Toudou[\(slug)]: push \(ops.count) op(s) → \(ops.map { "\($0.kind.rawValue):\($0.id.prefix(8))" }.joined(separator: ", "))")
                let res = try await client.push(list: slug, ops)
                print("Sync Toudou[\(slug)]: réponse push \(res.applied.map { "\($0.id.prefix(8))=\($0.status)" }.joined(separator: ", "))")
                store.applyPushApplied(res.applied)
            }
            let pull = try await client.pull(list: slug, since: cursor(slug))
            if !pull.tasks.isEmpty { print("Sync Toudou[\(slug)]: pull \(pull.tasks.count) tâche(s)") }
            store.applyPulled(pull.tasks, forList: list)
            setCursor(slug, pull.serverTime)
        } catch {
            print("Sync Toudou[\(slug)] échouée : \(error)")
        }
    }

    /// Curseur de delta par liste (dernier `serverTime` reçu pour ce slug), persisté en ISO 8601.
    private func cursor(_ slug: String) -> Date? {
        UserDefaults.standard.string(forKey: "toudouLastServerTime_\(slug)").flatMap { ToudouClient.parseDate($0) }
    }
    private func setCursor(_ slug: String, _ date: Date) {
        UserDefaults.standard.set(ToudouClient.formatDate(date), forKey: "toudouLastServerTime_\(slug)")
    }
}
