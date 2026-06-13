//
//  ListsView.swift
//  AssistToDoiOS
//
//  Vue de dispatch (parité Mac) : 4 zones — À faire (liste interne synced), Rappels Apple
//  (live iCloud, aujourd'hui + en retard), Agenda Apple (live, aujourd'hui), Fait (historique
//  coché). Deux dispositions commutables dans les Réglages : segmentée ou empilée.
//  Gestes de swipe répliqués du Mac (Fait/Modifier/Déplacer · Supprimer/Demain).
//

import SwiftUI
import AssistToDoCore
import AssistToDoKit

enum DispatchZone: String, CaseIterable, Identifiable {
    case todo = "À faire"
    case reminders = "Rappels"
    case agenda = "Agenda"
    case done = "Fait"
    var id: String { rawValue }
}

struct ListsView: View {
    @EnvironmentObject private var store: TaskStore
    @AppStorage("iosLayout") private var layout = "segmented"   // "segmented" | "stacked"

    @State private var zone: DispatchZone = .todo
    @State private var dueReminders: [TodayItem] = []
    @State private var editingTask: TaskRecord?
    @State private var editText = ""
    @State private var showDone = false

    var body: some View {
        Group {
            if layout == "stacked" { stackedLayout } else { segmentedLayout }
        }
        .task { await refreshReminders() }
        .refreshable {
            SyncCoordinator.shared?.syncNow()
            await store.refreshToday()
            await refreshReminders()
        }
        .alert("Modifier", isPresented: editingBinding) {
            TextField("Texte", text: $editText)
            Button("Annuler", role: .cancel) { editingTask = nil }
            Button("OK") {
                if let t = editingTask { store.updateText(id: t.id, text: editText) }
                editingTask = nil
            }
        }
    }

    // MARK: - Disposition segmentée

    private var segmentedLayout: some View {
        VStack(spacing: 0) {
            Picker("Zone", selection: $zone) {
                ForEach(DispatchZone.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 6)

            List {
                switch zone {
                case .todo:      todoRows
                case .reminders: reminderRows
                case .agenda:    eventRows
                case .done:      doneRows
                }
            }
        }
    }

    // MARK: - Disposition empilée (À faire + Rappels + Agenda en scroll, Fait via l'horloge)

    private var stackedLayout: some View {
        List {
            Section("À faire") { todoRows }
            Section("Rappels · aujourd'hui + en retard") { reminderRows }
            Section("Agenda · aujourd'hui") { eventRows }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showDone = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("Historique (fait)")
            }
        }
        .sheet(isPresented: $showDone) {
            NavigationStack {
                List { doneRows }
                    .navigationTitle("Fait")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { showDone = false } } }
            }
        }
    }

    // MARK: - Contenus des zones

    @ViewBuilder private var todoRows: some View {
        let items = (store.thoughts.filter { $0.destination == .local } + store.codeTasks)
            .filter { !$0.isDone }
        if items.isEmpty { emptyRow("Parle pour ajouter une tâche") }
        ForEach(items) { taskRow($0) }
    }

    @ViewBuilder private var doneRows: some View {
        let items = (store.thoughts + store.codeTasks).filter { $0.isDone }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        if items.isEmpty { emptyRow("Rien de coché pour l'instant") }
        ForEach(items) { taskRow($0) }
    }

    @ViewBuilder private var reminderRows: some View {
        if dueReminders.isEmpty { emptyRow("Aucun rappel dû") }
        ForEach(dueReminders) { reminderRow($0) }
    }

    @ViewBuilder private var eventRows: some View {
        if store.todayEvents.isEmpty { emptyRow("Aucun événement aujourd'hui") }
        ForEach(store.todayEvents) { eventRow($0) }
    }

    // MARK: - Lignes

    private func taskRow(_ rec: TaskRecord) -> some View {
        HStack(spacing: 12) {
            Button { store.toggleDone(id: rec.id) } label: {
                Image(systemName: rec.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(rec.isDone ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            if rec.localList == .code {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption2).foregroundStyle(.purple)
            }
            Text(rec.text)
                .strikethrough(rec.isDone)
                .foregroundStyle(rec.isDone ? .secondary : .primary)
            Spacer()
            if rec.destination == .reminders {
                Image(systemName: "bell").font(.caption).foregroundStyle(.secondary)
            }
        }
        // Swipe gauche→droite (parité Mac) : Fait · Modifier · Déplacer.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { store.toggleDone(id: rec.id) } label: { Label("Fait", systemImage: "checkmark.circle") }.tint(.green)
            if rec.destination != .reminders {
                Button { startEditing(rec) } label: { Label("Modifier", systemImage: "pencil") }.tint(.blue)
            }
            if rec.destination == .local {
                Button { store.moveToList(id: rec.id, to: rec.localList == .code ? .braindump : .code) } label: {
                    Label(rec.localList == .code ? "Cerveau" : "Code", systemImage: "arrow.left.arrow.right")
                }.tint(.purple)
            }
        }
        // Swipe droite→gauche (parité Mac) : Supprimer · Demain.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { store.delete(id: rec.id) } label: { Label("Supprimer", systemImage: "trash") }
            if rec.destination == .local {
                Button { store.postponeToTomorrow(id: rec.id) } label: { Label("Demain", systemImage: "arrow.uturn.forward") }.tint(.orange)
            }
        }
        .contextMenu {
            Button(rec.isDone ? "Marquer non faite" : "Marquer faite") { store.toggleDone(id: rec.id) }
            if rec.destination != .reminders { Button("Modifier") { startEditing(rec) } }
            if rec.destination == .local {
                Button(rec.localList == .code ? "Vers Vidage de cerveau" : "Vers Claude Code") {
                    store.moveToList(id: rec.id, to: rec.localList == .code ? .braindump : .code)
                }
                Button("Reporter à demain") { store.postponeToTomorrow(id: rec.id) }
            }
            Divider()
            Button("Supprimer", role: .destructive) { store.delete(id: rec.id) }
        }
    }

    private func reminderRow(_ item: TodayItem) -> some View {
        HStack(spacing: 12) {
            Button {
                EventKitService.shared.setReminderCompleted(id: item.id, completed: true)
                Task { await refreshReminders() }
            } label: {
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Image(systemName: "bell").font(.caption).foregroundStyle(.orange)
            Text(item.title)
            Spacer()
            if let d = item.date {
                Text(d, style: .time).font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                EventKitService.shared.setReminderCompleted(id: item.id, completed: true)
                Task { await refreshReminders() }
            } label: { Label("Fait", systemImage: "checkmark.circle") }.tint(.green)
        }
    }

    private func eventRow(_ item: TodayItem) -> some View {
        HStack {
            Image(systemName: "calendar").foregroundStyle(.blue)
            Text(item.title)
            Spacer()
            if let d = item.date {
                Text(d, style: .time).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Journée").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).font(.callout)
    }

    // MARK: - Édition / données

    private var editingBinding: Binding<Bool> {
        Binding(get: { editingTask != nil }, set: { if !$0 { editingTask = nil } })
    }

    private func startEditing(_ task: TaskRecord) {
        editText = task.text
        editingTask = task
    }

    private func refreshReminders() async {
        dueReminders = await EventKitService.shared.fetchDueReminders()
    }
}
