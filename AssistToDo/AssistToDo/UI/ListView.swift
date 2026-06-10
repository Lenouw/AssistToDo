//
//  ListView.swift
//  AssistToDo
//
//  Liste des tâches du jour. Observe TaskStore (source unique).
//

import SwiftUI
import AssistToDoCore

struct ListView: View {
    @ObservedObject var store: TaskStore
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Aujourd'hui")
                    .font(.headline)
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Réglages")
                .accessibilityLabel("Ouvrir les réglages")
            }

            if store.tasks.isEmpty {
                Text("Aucune tâche")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.tasks) { task in
                        TaskRow(task: task) { store.toggleDone(id: task.id) }
                    }
                }
                .listStyle(.inset)
            }

            Text("Build \(BuildInfo.date)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 360, height: 440)
    }
}

private struct TaskRow: View {
    let task: TaskRecord
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Marquer non faite" : "Marquer faite")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.text)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                if let sub = subtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if task.rolloverCount >= 3 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Reportée \(task.rolloverCount) fois")
                    .accessibilityLabel("Tâche reportée \(task.rolloverCount) fois")
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let remind = task.remindAt {
            parts.append("🔔 " + Self.timeFormatter.string(from: remind))
        }
        if let p = task.priority { parts.append("priorité " + p.rawValue) }
        if !task.tags.isEmpty { parts.append(task.tags.map { "#\($0)" }.joined(separator: " ")) }
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
