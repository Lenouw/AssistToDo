//
//  OpenRouterClient.swift
//  AssistToDoKit
//
//  Appel à l'API OpenRouter (chat/completions) pour parser le texte transcrit.
//  Clé lue depuis le Keychain. Timeout court (chemin de capture).
//

import Foundation

public struct OpenRouterClient {
    public enum ClientError: Error, LocalizedError {
        case noKey, badResponse, apiError(String), httpStatus(Int, String)
        public var errorDescription: String? {
            switch self {
            case .noKey: return "Aucune clé OpenRouter (à mettre dans les Réglages)"
            case .badResponse: return "Réponse inattendue de l'API"
            case .apiError(let m): return "Erreur API : \(m)"
            case .httpStatus(let code, let m):
                let base = code == 401 ? "clé invalide ou expirée (401)"
                    : code == 429 ? "quota dépassé / rate-limit (429)"
                    : "erreur HTTP \(code)"
                return m.isEmpty ? base : "\(base) — \(m)"
            }
        }
    }

    let model: String
    let timeout: TimeInterval

    /// 30 s (et non 8) : la réponse n'est PAS streamée, donc le timeout doit couvrir la
    /// génération complète du modèle. À 8 s, sur iPhone (Wi-Fi/4G + latence OpenRouter),
    /// le parse échouait par timeout → repli « texte brut » → la capture atterrissait dans
    /// « À faire » sans rappel ni événement. Personne n'attend devant l'écran (le toast est
    /// déjà affiché, le traitement est en tâche de fond) : mieux vaut patienter que rater.
    public init(model: String, timeout: TimeInterval = 30) {
        self.model = model
        self.timeout = timeout
    }

    /// Un timeout / une coupure réseau passagère ne doit pas coûter la structuration de la
    /// capture : on retente une fois avant d'abandonner (les autres erreurs remontent direct).
    public func complete(system: String, user: String) async throws -> String {
        do {
            return try await send(system: system, user: user)
        } catch let error as URLError where Self.isTransient(error) {
            return try await send(system: system, user: user)
        }
    }

    private static func isTransient(_ error: URLError) -> Bool {
        [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]
            .contains(error.code)
    }

    private func send(system: String, user: String) async throws -> String {
        let key = KeychainStore.apiKey()
        guard !key.isEmpty else { throw ClientError.noKey }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Code HTTP d'abord : un 401 (clé invalide) / 429 (quota) / 5xx doit être identifiable
        // dans les logs, pas noyé dans un `badResponse` générique.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = (json?["error"] as? [String: Any])?["message"] as? String ?? ""
            throw ClientError.httpStatus(http.statusCode, msg)
        }
        if let error = json?["error"] as? [String: Any], let message = error["message"] as? String {
            throw ClientError.apiError(message)
        }
        guard
            let choices = json?["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw ClientError.badResponse }

        return content
    }
}
