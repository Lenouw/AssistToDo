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
            todayHeader
            Picker("Zone", selection: $zone) {
                ForEach(DispatchZone.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.bottom, 8)

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
        VStack(spacing: 0) {
            todayHeader
            List {
                Section("À faire") { todoRows }
                Section("Rappels") { reminderRows }
                Section("Agenda · aujourd'hui") { eventRows }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.atdBg.ignoresSafeArea())
        }
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
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.atdBg.ignoresSafeArea())
                    .navigationTitle("Fait")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { showDone = false } } }
            }
        }
    }

    // MARK: - Contenus des zones

    /// En-tête : la journée de l'utilisateur, pas le nom de l'app.
    private var todayHeader: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Aujourd'hui").font(.largeTitle.bold()).foregroundStyle(Color.atdInk)
            Text(Self.headerDate.string(from: Date()).capitalizedFirst)
                .font(.subheadline).foregroundStyle(Color.atdInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)
        .background(Color.atdBg)
    }

    @ViewBuilder private var todoRows: some View {
        let items = (store.thoughts.filter { $0.destination == .local } + store.codeTasks)
            .filter { !$0.isDone }
            .sorted { priorityRank($0) < priorityRank($1) }
        if items.isEmpty {
            emptyState("Cerveau vide", "Maintiens le micro pour vider ce que tu as en tête.", "sparkles")
        }
        ForEach(items) { taskRow($0) }
    }

    /// Ordre d'affichage : haute en premier, puis moyenne, non priorisée, basse en dernier.
    private func priorityRank(_ r: TaskRecord) -> Int {
        switch r.priority {
        case .haut:  return 0
        case .moyen: return 1
        case nil:    return 2
        case .bas:   return 3
        }
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
        let high = rec.priority == .haut && !rec.isDone
        let low = rec.priority == .bas
        return HStack(alignment: .top, spacing: 12) {
            Button {
                Haptics.light()
                store.toggleDone(id: rec.id)
            } label: {
                Image(systemName: rec.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(rec.isDone ? Color.atdSuccess : Color.atdInkTertiary)
                    .symbolEffect(.bounce, value: rec.isDone)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Priorité haute = drapeau chaud + texte semibold → saute aux yeux.
                    if high {
                        Image(systemName: "flag.fill").font(.caption2).foregroundStyle(Color.atdPriorityHigh)
                    }
                    if rec.localList == .code {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.caption2).foregroundStyle(Color.atdCode)
                    }
                    Text(rec.text)
                        .font(high ? .body.weight(.semibold) : .body)
                        .strikethrough(rec.isDone)
                        .foregroundStyle(rec.isDone ? Color.atdInkTertiary
                                         : (low ? Color.atdInkSecondary : Color.atdInk))
                }
                taskMeta(rec)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        // Priorité haute : fond de ligne légèrement teinté (hiérarchie sans bordure latérale).
        .listRowBackground(high ? Color.atdPriorityHigh.opacity(0.06) : Color.clear)
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
        let overdue = (item.date ?? .distantFuture) < Date()
        return HStack(alignment: .top, spacing: 12) {
            Button { Haptics.light(); completeReminder(item.id) } label: {
                Image(systemName: "circle").font(.system(size: 21)).foregroundStyle(Color.atdInkTertiary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).foregroundStyle(Color.atdInk)
                if let d = item.date {
                    HStack(spacing: 4) {
                        Image(systemName: overdue ? "exclamationmark.circle.fill" : "bell")
                        Text(overdue ? "En retard · " : "").bold() + Text(d, style: .date)
                    }
                    .font(.caption)
                    .foregroundStyle(overdue ? Color.atdRecording : Color.atdInkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { completeReminder(item.id) } label: { Label("Fait", systemImage: "checkmark.circle") }.tint(.green)
        }
    }

    /// Événement en mini-bloc horaire : heure en gras à gauche, repère de temps, titre.
    private func eventRow(_ item: TodayItem) -> some View {
        HStack(spacing: 12) {
            Group {
                if let d = item.date {
                    Text(d, style: .time).font(.subheadline.weight(.semibold)).foregroundStyle(Color.atdInk)
                } else {
                    Text("Jour").font(.caption.weight(.medium)).foregroundStyle(Color.atdInkSecondary)
                }
            }
            .frame(width: 50, alignment: .leading)
            Capsule().fill(Color.atdZoneAgenda).frame(width: 3, height: 26)
            Text(item.title).foregroundStyle(Color.atdInk)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func permissionRow(_ label: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(label, systemImage: "lock.open")
        }
    }

    /// Méta sous le libellé : n'affiche une échéance que pour les rappels datés (sinon = bruit).
    @ViewBuilder private func taskMeta(_ rec: TaskRecord) -> some View {
        if rec.destination == .reminders, let d = rec.remindAt ?? rec.dueDate {
            HStack(spacing: 4) {
                Image(systemName: "bell")
                Text(d, style: .date)
            }
            .font(.caption).foregroundStyle(Color.atdInkSecondary)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).foregroundStyle(Color.atdInkSecondary).font(.callout)
    }

    /// Vide invitant (au lieu d'une ligne grise) pour la zone principale.
    private func emptyState(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Color.atdAccent.opacity(0.55))
            Text(title).font(.headline).foregroundStyle(Color.atdInk)
            Text(subtitle).font(.subheadline).foregroundStyle(Color.atdInkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
        .listRowBackground(Color.clear)
    }

    private static let headerDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = ParisCalendar.tz
        f.dateFormat = "EEEE d MMMM"; return f
    }()

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

private extension String {
    /// "vendredi 20 juin" → "Vendredi 20 juin".
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
