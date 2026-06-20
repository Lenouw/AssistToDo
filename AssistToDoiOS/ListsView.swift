//
//  ListsView.swift
//  AssistToDoiOS
//
//  Vue de dispatch (parité Mac) : 4 zones — À faire (liste interne synced), Rappels Apple
//  (live iCloud : dûs aujourd'hui/en retard + à venir), Agenda Apple (live, aujourd'hui),
//  Fait (historique coché). Deux dispositions commutables (Réglages) : segmentée ou empilée.
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

/// Disposition de l'écran (typée plutôt que String brute, partagée avec les Réglages).
enum AppLayout: String { case segmented, stacked }

struct ListsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: AppModel
    @AppStorage("iosLayout") private var layout: AppLayout = .segmented

    @State private var zone: DispatchZone = .todo
    @State private var openReminders: [TodayItem] = []   // tous les rappels datés non terminés
    @State private var editingTask: TaskRecord?
    @State private var editText = ""
    @State private var showDone = false

    var body: some View {
        Group {
            if layout == .stacked { stackedLayout } else { segmentedLayout }
        }
        .task { await refreshReminders() }
        .refreshable {
            SyncCoordinator.shared?.syncNow()
            await store.refreshToday()
            await refreshReminders()
        }
        .onChange(of: zone) { _, z in
            Task {
                if z == .reminders { await refreshReminders() }
                if z == .agenda { await store.refreshToday() }
            }
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color.atdBg.ignoresSafeArea())
    }

    // MARK: - Disposition empilée (À faire + Rappels + Agenda en scroll, Fait via l'horloge)

    private var stackedLayout: some View {
        List {
            Section("À faire") { todoRows }
            Section("Rappels") { reminderRows }
            Section("Agenda · aujourd'hui") { eventRows }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.atdBg.ignoresSafeArea())
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
        if !EventKitService.shared.hasRemindersAccess {
            permissionRow("Autoriser les rappels") {
                await model.requestRemindersAndCalendar(); await refreshReminders()
            }
        } else {
            let end = endOfToday
            let due = openReminders.filter { ($0.date ?? .distantPast) < end }
            let upcoming = openReminders.filter { ($0.date ?? .distantFuture) >= end }
            if due.isEmpty && upcoming.isEmpty { emptyRow("Aucun rappel") }
            ForEach(due) { reminderRow($0) }
            if !upcoming.isEmpty {
                Text("À venir").font(.caption).foregroundStyle(.secondary)
                ForEach(upcoming) { reminderRow($0) }
            }
        }
    }

    @ViewBuilder private var eventRows: some View {
        if !EventKitService.shared.hasCalendarAccess {
            permissionRow("Autoriser le calendrier") {
                await model.requestRemindersAndCalendar(); await store.refreshToday()
            }
        } else if store.todayEvents.isEmpty {
            emptyRow("Aucun événement aujourd'hui")
        } else {
            ForEach(store.todayEvents) { eventRow($0) }
        }
    }

    // MARK: - Lignes

    private func taskRow(_ rec: TaskRecord) -> some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                store.toggleDone(id: rec.id)
            } label: {
                Image(systemName: rec.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(rec.isDone ? Color.atdAccent : Color.atdInkSecondary)
                    .symbolEffect(.bounce, value: rec.isDone)
            }
            .buttonStyle(.plain)
            if rec.localList == .code {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption2).foregroundStyle(Color.atdCode)
            }
            Text(rec.text)
                .strikethrough(rec.isDone)
                .foregroundStyle(rec.isDone ? Color.atdInkSecondary : Color.atdInk)
            Spacer()
            if rec.destination == .reminders {
                Image(systemName: "bell").font(.caption).foregroundStyle(Color.atdZoneReminders)
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
            Button { Haptics.light(); completeReminder(item.id) } label: {
                Image(systemName: "circle").foregroundStyle(Color.atdInkSecondary)
            }
            .buttonStyle(.plain)
            Image(systemName: "bell").font(.caption).foregroundStyle(Color.atdZoneReminders)
            Text(item.title).foregroundStyle(Color.atdInk)
            Spacer()
            if let d = item.date {
                Text(d, style: .date).font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { completeReminder(item.id) } label: { Label("Fait", systemImage: "checkmark.circle") }.tint(.green)
        }
    }

    private func eventRow(_ item: TodayItem) -> some View {
        HStack {
            Image(systemName: "calendar").foregroundStyle(Color.atdZoneAgenda)
            Text(item.title).foregroundStyle(Color.atdInk)
            Spacer()
            if let d = item.date {
                Text(d, style: .time).font(.caption).foregroundStyle(Color.atdInkSecondary)
            } else {
                Text("Journée").font(.caption).foregroundStyle(Color.atdInkSecondary)
            }
        }
    }

    private func permissionRow(_ label: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(label, systemImage: "lock.open")
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).font(.callout)
    }

    // MARK: - Actions / données

    private var endOfToday: Date {
        let start = ParisCalendar.startOfDay(for: Date())
        return ParisCalendar.calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }

    private var editingBinding: Binding<Bool> {
        Binding(get: { editingTask != nil }, set: { if !$0 { editingTask = nil } })
    }

    private func startEditing(_ task: TaskRecord) {
        editText = task.text
        editingTask = task
    }

    private func completeReminder(_ id: String) {
        EventKitService.shared.setReminderCompleted(id: id, completed: true)
        Task { await refreshReminders() }
    }

    private func refreshReminders() async {
        openReminders = await EventKitService.shared.fetchOpenReminders()
    }
}
