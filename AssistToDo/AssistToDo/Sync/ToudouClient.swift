//
//  ToudouClient.swift
//  AssistToDo
//
//  Client HTTP de synchronisation avec Toudou (source de vérité). Contrat défini par
//  Toudou : GET /api/sync?since=<iso> (pull delta) + POST /api/sync (push ops), Bearer token.
//  Voir spec : App - Toudou/docs/superpowers/specs/2026-06-12-toudou-sync-design.md
//

import Foundation

/// Format d'une tâche échangée (wire).
struct WireTask: Decodable {
    let id: String
    let text: String
    let done: Bool
    let updatedAt: Date
    let deleted: Bool

    enum CodingKeys: String, CodingKey { case id, text, done, updatedAt, deleted }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        deleted = (try? c.decode(Bool.self, forKey: .deleted)) ?? false
        let iso = (try? c.decode(String.self, forKey: .updatedAt)) ?? ""
        updatedAt = ToudouClient.parseDate(iso) ?? .distantPast
    }
}

enum SyncOpKind: String { case create, update, delete }

/// Une opération à pousser. `text`/`done` selon le type (cf. spec §6.2).
struct SyncOp {
    let kind: SyncOpKind
    let id: String
    let text: String?
    let done: Bool?
    let updatedAt: Date
}

struct AppliedResult { let id: String; let status: String }   // status: "applied" | "ignored-stale"

final class ToudouClient {
    enum SyncError: Error { case notConfigured, badURL, http(Int), badResponse }

    private var baseURL: String { (UserDefaults.standard.string(forKey: "toudouBaseURL") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var token: String { KeychainStore.toudouToken() }

    var isConfigured: Bool { !baseURL.isEmpty && !token.isEmpty && URL(string: endpoint("/api/sync")) != nil }

    private func endpoint(_ path: String) -> String {
        var b = baseURL
        if b.hasSuffix("/") { b.removeLast() }
        return b + path
    }

    // MARK: - Pull (delta)

    func pull(since: Date?) async throws -> (serverTime: Date, tasks: [WireTask]) {
        guard isConfigured else { throw SyncError.notConfigured }
        guard var comps = URLComponents(string: endpoint("/api/sync")) else { throw SyncError.badURL }
        if let since { comps.queryItems = [URLQueryItem(name: "since", value: Self.formatDate(since))] }
        guard let url = comps.url else { throw SyncError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.checkStatus(resp)

        struct PullResp: Decodable {
            let serverTime: Date
            let tasks: [WireTask]
            enum K: String, CodingKey { case serverTime, tasks }
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: K.self)
                serverTime = ToudouClient.parseDate((try? c.decode(String.self, forKey: .serverTime)) ?? "") ?? Date()
                tasks = (try? c.decode([WireTask].self, forKey: .tasks)) ?? []
            }
        }
        let r = try JSONDecoder().decode(PullResp.self, from: data)
        return (r.serverTime, r.tasks)
    }

    // MARK: - Push (ops)

    func push(_ ops: [SyncOp]) async throws -> (serverTime: Date, applied: [AppliedResult]) {
        guard isConfigured else { throw SyncError.notConfigured }
        guard let url = URL(string: endpoint("/api/sync")) else { throw SyncError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let opsJSON: [[String: Any]] = ops.map { op in
            var d: [String: Any] = ["op": op.kind.rawValue, "id": op.id, "updatedAt": Self.formatDate(op.updatedAt)]
            if let t = op.text { d["text"] = t }
            if let dn = op.done { d["done"] = dn }
            return d
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["ops": opsJSON])

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.checkStatus(resp)

        struct PushResp: Decodable {
            let serverTime: String?
            let applied: [Item]?
            struct Item: Decodable { let id: String; let status: String }
        }
        let r = try JSONDecoder().decode(PushResp.self, from: data)
        let st = Self.parseDate(r.serverTime ?? "") ?? Date()
        return (st, (r.applied ?? []).map { AppliedResult(id: $0.id, status: $0.status) })
    }

    // MARK: - Utilitaires

    private static func checkStatus(_ resp: URLResponse) throws {
        guard let h = resp as? HTTPURLResponse else { throw SyncError.badResponse }
        guard (200..<300).contains(h.statusCode) else { throw SyncError.http(h.statusCode) }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    static func formatDate(_ d: Date) -> String { iso.string(from: d) }
}
