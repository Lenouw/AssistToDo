//
//  ShoppingView.swift
//  AssistToDoiOS
//
//  Liste de courses in-app (sous-liste locale "shopping") : remplace Apple Notes,
//  indisponible sur iOS. Cases cochables contrôlées par l'app. Pas de sync (v1).
//

import SwiftUI
import AssistToDoCore
import AssistToDoKit

struct ShoppingView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var newItem = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Ajouter un article", text: $newItem)
                            .onSubmit(add)
                        Button(action: add) { Image(systemName: "plus.circle.fill") }
                            .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("À acheter") {
                    if store.shoppingItems.isEmpty {
                        Text("Liste vide").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(store.shoppingItems) { item in
                        HStack {
                            Button { store.toggleDone(id: item.id) } label: {
                                Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(item.isDone ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            Text(item.text).strikethrough(item.isDone)
                                .foregroundStyle(item.isDone ? .secondary : .primary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.delete(id: item.id) } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Courses")
        }
    }

    private func add() {
        let text = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.add([TaskRecord(text: text, createdAt: Date(),
                              dueDate: ParisCalendar.startOfDay(for: Date()),
                              localList: .shopping)])
        newItem = ""
    }
}
