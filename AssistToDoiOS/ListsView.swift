//
//  ListsView.swift
//  AssistToDoiOS
//
//  Second cerveau : vidage de cerveau (+ Rappels Apple du jour), to-do Claude Code,
//  et agenda du jour (lecture seule). Synchronisé avec Toudou (braindump + code).
//

import SwiftUI
import AssistToDoCore
import AssistToDoKit

struct ListsView: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        List {
            Section("Vidage de cerveau") {
                if store.thoughts.isEmpty { emptyRow("Parle pour ajouter une note") }
                ForEach(store.thoughts) { taskRow($0) }
            }
            if !store.codeTasks.isEmpty {
                Section("Claude Code") {
                    ForEach(store.codeTasks) { taskRow($0) }
                }
            }
            if !store.todayEvents.isEmpty || !store.todayReminders.isEmpty {
                Section("Aujourd'hui · iCloud") {
                    ForEach(store.todayEvents) { todayRow($0) }
                    ForEach(store.todayReminders) { todayRow($0) }
                }
            }
        }
        .refreshable {
            SyncCoordinator.shared?.syncNow()
            await store.refreshToday()
        }
    }

    private func taskRow(_ rec: TaskRecord) -> some View {
        HStack(spacing: 12) {
            Button { store.toggleDone(id: rec.id) } label: {
                Image(systemName: rec.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(rec.isDone ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            Text(rec.text)
                .strikethrough(rec.isDone)
                .foregroundStyle(rec.isDone ? .secondary : .primary)
            Spacer()
            if rec.destination == .reminders {
                Image(systemName: "bell").font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.delete(id: rec.id) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func todayRow(_ item: TodayItem) -> some View {
        HStack {
            Image(systemName: item.isEvent ? "calendar" : "bell").foregroundStyle(.secondary)
            Text(item.title)
            Spacer()
            if let d = item.date {
                Text(d, style: .time).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).font(.callout)
    }
}
