//
//  IslandView.swift
//  AssistToDo
//
//  Îlot compact en verre dépoli (matériau translucide + flou), ancré sous l'encoche.
//  Morphe entre écoute (ondes) → transcription → texte → ✓ ajouté.
//

import SwiftUI
import AssistToDoCore

struct IslandView: View {
    @ObservedObject var audio: AudioCapture
    @ObservedObject var model: CaptureModel

    var body: some View {
        VStack(spacing: 0) {
            // Zone transparente derrière l'encoche (rien dessiné dessus).
            Color.clear.frame(height: model.topInset)
            pill
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.state)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.addedItems.count)
    }

    private var pill: some View {
        content
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .preparing:
            row(dot: .yellow, text: "Préparation…")
        case .listening:
            HStack(spacing: 10) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Waveform(level: audio.level).frame(height: 18)
                Text("Parle…").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Traitement…").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        case .result:
            HStack(spacing: 8) {
                Image(systemName: "text.quote").font(.caption).foregroundStyle(.tertiary)
                Text(model.transcript)
                    .font(.callout).foregroundStyle(.primary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        case .added:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .symbolEffect(.bounce, value: model.addedItems.count)
                    Text(model.addedItems.count > 1 ? "\(model.addedItems.count) tâches ajoutées" : "Tâche ajoutée")
                        .font(.callout.weight(.medium)).foregroundStyle(.primary)
                }
                ForEach(model.addedItems) { item in
                    HStack(spacing: 6) {
                        Image(systemName: Self.icon(item.destination))
                            .font(.caption2).foregroundStyle(item.fellBack ? .orange : .secondary)
                        Text(label(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        case .ignored:
            row(dot: .gray, text: "Rien à ajouter")
        case .error:
            row(dot: .red, text: model.transcript.isEmpty ? "Rien entendu" : model.transcript)
        }
    }

    private func row(dot: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func label(_ item: ToastItem) -> String {
        if item.fellBack { return item.record.text + " · liste locale" }
        let dest: String
        switch item.destination {
        case .local: dest = "Ma liste"
        case .reminders: dest = "Rappels"
        case .calendar: dest = "Calendrier"
        case .notes: dest = "Notes"
        }
        return item.record.text + " · " + dest
    }

    static func icon(_ d: Destination) -> String {
        switch d {
        case .local: return "checklist"
        case .reminders: return "list.bullet.circle"
        case .calendar: return "calendar"
        case .notes: return "note.text"
        }
    }
}

/// Ondes centrées réagissant au volume, teintées accent.
private struct Waveform: View {
    var level: Float
    private let barCount = 15

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule().fill(Color.accentColor.opacity(0.9)).frame(width: 2.5, height: barHeight(i))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let dist = abs(Double(i) - center) / center
        let shape = 1 - dist * 0.7
        return 3 + Double(level) * 15 * shape
    }
}
