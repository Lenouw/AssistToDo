//
//  IslandView.swift
//  AssistToDo
//
//  Îlot type Dynamic Island ancré à l'encoche : pill noir qui morphe entre
//  écoute (ondes) → transcription → texte → ✓ ajouté.
//

import SwiftUI
import AssistToDoCore

struct IslandView: View {
    @ObservedObject var audio: AudioCapture
    @ObservedObject var model: CaptureModel

    var body: some View {
        VStack(spacing: 0) {
            // Zone derrière l'encoche physique : laissée vide.
            Color.clear.frame(height: model.topInset)
            // Contenu visible, centré dans la partie sous l'encoche.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.state)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.addedItems.count)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .preparing:
            row(dot: .yellow, text: "Préparation…")
        case .listening:
            HStack(spacing: 12) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Waveform(level: audio.level).frame(height: 22)
                Text("Parle…").font(.callout).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 18)
        case .transcribing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Traitement…").font(.callout).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 18)
        case .result:
            HStack(spacing: 10) {
                Image(systemName: "text.quote").foregroundStyle(.white.opacity(0.6))
                Text(model.transcript)
                    .font(.callout).foregroundStyle(.white)
                    .lineLimit(3).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        case .added:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .symbolEffect(.bounce, value: model.addedItems.count)
                    Text(model.addedItems.count > 1 ? "\(model.addedItems.count) tâches ajoutées" : "Tâche ajoutée")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                ForEach(model.addedItems) { item in
                    HStack(spacing: 6) {
                        Image(systemName: Self.icon(item.destination))
                            .font(.caption2).foregroundStyle(item.fellBack ? .orange : .white.opacity(0.7))
                        Text(label(item)).font(.caption).foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        case .error:
            row(dot: .red, text: model.transcript.isEmpty ? "Rien entendu" : model.transcript)
        }
    }

    private func row(dot: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 18)
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

/// Ondes centrées réagissant au volume.
private struct Waveform: View {
    var level: Float
    private let barCount = 17

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule().fill(.white.opacity(0.9)).frame(width: 3, height: barHeight(i))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let dist = abs(Double(i) - center) / center
        let shape = 1 - dist * 0.7
        return 3 + Double(level) * 20 * shape
    }
}
