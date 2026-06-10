//
//  ToastView.swift
//  AssistToDo
//
//  Toast de confirmation des tâches créées (haut-droite, informatif).
//

import SwiftUI
import AssistToDoCore

@MainActor
final class ToastModel: ObservableObject {
    @Published var records: [TaskRecord] = []
}

struct ToastView: View {
    @ObservedObject var model: ToastModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(model.records.count > 1 ? "\(model.records.count) tâches ajoutées" : "Tâche ajoutée")
                    .font(.subheadline.bold())
            }
            ForEach(model.records) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.text)
                        .font(.callout)
                        .lineLimit(2)
                    if let sub = subtitle(record) {
                        Text(sub).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1)))
    }

    private func subtitle(_ r: TaskRecord) -> String? {
        var parts: [String] = []
        if let remind = r.remindAt {
            parts.append("🔔 " + Self.timeFormatter.string(from: remind))
        }
        if let p = r.priority { parts.append("priorité " + p.rawValue) }
        if !r.tags.isEmpty { parts.append(r.tags.map { "#\($0)" }.joined(separator: " ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM HH:mm"
        return f
    }()
}
