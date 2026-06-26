//
//  ArchiveView.swift
//  AssistToDo
//
//  Archive : tâches marquées « fait » depuis plus de 24h, sorties des listes actives.
//  Restaurer (re-décocher → revient dans sa liste) ou supprimer définitivement.
//

import SwiftUI
import AssistToDoKit

struct ArchiveView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        Group {
            if store.archived.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "archivebox").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Aucune tâche archivée").foregroundStyle(.secondary)
                    Text("Les tâches faites arrivent ici 24h après avoir été cochées").font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            } else {
                List {
                    ForEach(store.archived) { task in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.text).font(.system(size: 12)).strikethrough()
                                    .foregroundStyle(.secondary).lineLimit(2)
                                if let d = task.doneAt {
                                    Text("Fait le \(Self.df.string(from: d))").font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .help(task.text)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { store.delete(id: task.id) } label: { Label("Supprimer", systemImage: "trash") }.labelStyle(.titleAndIcon)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { store.toggleDone(id: task.id) } label: { Label("Restaurer", systemImage: "arrow.uturn.backward") }.labelStyle(.titleAndIcon).tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM 'à' HH:mm"; return f
    }()
}
