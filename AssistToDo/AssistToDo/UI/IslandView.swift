//
//  IslandView.swift
//  AssistToDo
//
//  Îlot type Dynamic Island : noir translucide + flou, part de l'encoche (haut plat),
//  s'arrondit en bas, et grandit selon l'état. Écoute (ondes) → texte → ✓ ajouté.
//

import SwiftUI
import AssistToDoCore

struct IslandView: View {
    @ObservedObject var audio: AudioCapture
    @ObservedObject var model: CaptureModel

    private var shape: some InsettableShape {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 22,
                               bottomTrailingRadius: 22, topTrailingRadius: 0, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Zone derrière l'encoche : couverte par le fond noir (effet "ça sort du notch").
            Color.clear.frame(height: model.topInset)
            content
        }
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)   // flou
                Rectangle().fill(.black.opacity(0.55)) // teinte noire translucide
            }
            .environment(\.colorScheme, .dark)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.state)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.addedItems.count)
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
                Text("Parle…").font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Traitement…").font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
        case .result:
            HStack(spacing: 8) {
                Image(systemName: "text.quote").font(.caption).foregroundStyle(.white.opacity(0.5))
                Text(model.transcript)
                    .font(.callout).foregroundStyle(.white)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        case .added:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .symbolEffect(.bounce, value: model.addedItems.count)
                    Text(model.addedItems.count > 1 ? "\(model.addedItems.count) tâches ajoutées" : "Tâche ajoutée")
                        .font(.callout.weight(.medium)).foregroundStyle(.white)
                }
                ForEach(model.addedItems) { item in
                    HStack(spacing: 6) {
                        Image(systemName: Self.icon(item.destination))
                            .font(.caption2).foregroundStyle(item.fellBack ? .orange : .white.opacity(0.6))
                        Text(label(item)).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        case .ignored:
            row(dot: .gray, text: "Rien à ajouter")
        case .error:
            row(dot: .red, text: model.transcript.isEmpty ? "Rien entendu" : model.transcript)
        }
    }

    private func row(dot: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
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
    private let barCount = 15

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule().fill(.white.opacity(0.92)).frame(width: 2.5, height: barHeight(i))
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
