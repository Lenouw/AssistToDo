//
//  OpenRouterClient.swift
//  AssistToDo
//
//  Appel à l'API OpenRouter (chat/completions) pour parser le texte transcrit.
//  Clé lue depuis le Keychain. Timeout court (chemin de capture).
//

import Foundation

struct OpenRouterClient {
    enum ClientError: Error { case noKey, badResponse, apiError(String) }

    let model: String
    let timeout: TimeInterval

    init(model: String, timeout: TimeInterval = 8) {
        self.model = model
        self.timeout = timeout
    }

    func complete(system: String, user: String) async throws -> String {
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

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

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
