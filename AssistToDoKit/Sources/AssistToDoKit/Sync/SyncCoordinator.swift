//
//  SyncCoordinator.swift
//  AssistToDoKit
//
//  Pilote la synchro Toudou : à chaque cycle (lancement + timer ~45s + manuel),
//  push les ops locaux en attente PUIS pull le delta serveur (cf. spec §8).
//  Toudou est la source de vérité ; on n'envoie que les to-do "vide-tête".
//

import Foundation
import os
import AssistToDoCore

@MainActor
public final class SyncCoordinator {
    private let log = Logger(subsystem: "com.assisttodo", category: "Sync")
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
        log.notice("start: isConfigured=\(self.client.isConfigured, privacy: .public)")
        guard client.isConfigured else { return }
        // Au lancement : pull COMPLET (since=nil) → réconcilie tout l'état serveur. Indispensable
        // car le curseur peut être en avance sur un store local incomplet (ex : data perdue à une
        // migration) ; un delta `since=curseur` ne re-ramènerait jamais les tâches plus anciennes.
        // Les cycles suivants (timer 45 s) restent en delta pour rester légers.
        syncNow(full: true)
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
    }

    public func stop() { timer?.invalidate(); timer = nil }

    /// Un cycle complet : chaque liste indépendamment (push ses ops, puis pull). `full` = ignore le
    /// curseur et pull tout (réconciliation), sinon delta depuis le curseur.
    public func syncNow(full: Bool = false) {
        guard !syncing, client.isConfigured else { return }
        syncing = true
        Task { @MainActor in
            defer { self.syncing = false }
            for ch in self.channels { await self.syncList(slug: ch.slug, list: ch.list, full: full) }
        }
    }

    /// Synchronise une liste : push (ops en attente) avant pull.
    private func syncList(slug: String, list: LocalList, full: Bool) async {
        do {
            let ops = store.collectPendingOps(for: list)
            if !ops.isEmpty {
                let res = try await client.push(list: slug, ops)
                store.applyPushApplied(res.applied)
            }
            let since = full ? nil : cursor(slug)
            let pull = try await client.pull(list: slug, since: since)
            log.notice("\(slug, privacy: .public): pull \(pull.tasks.count, privacy: .public) tâche(s) (full=\(full, privacy: .public))")
            // Le curseur n'avance que si la persistance a réussi : sinon ces tâches seraient
            // perdues (jamais re-demandées car `since` aurait dépassé leur serverTime).
            if store.applyPulled(pull.tasks, forList: list) {
                setCursor(slug, pull.serverTime)
            } else {
                log.error("\(slug, privacy: .public): persistance échouée, curseur NON avancé")
            }
        } catch {
            log.error("\(slug, privacy: .public) échouée : \(error.localizedDescription, privacy: .public)")
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
