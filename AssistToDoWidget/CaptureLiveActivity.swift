//
//  CaptureLiveActivity.swift
//  AssistToDoWidget
//
//  Présentation de la capture en Dynamic Island (iPhone 14 Pro+) et sur l'écran verrouillé
//  (autres appareils) : écoute → traitement → ajouté.
//

import WidgetKit
import SwiftUI
import ActivityKit

// Accent "Clarté chaude" (le widget ne lie pas AssistToDoKit → couleur définie localement).
private let atdAccent = Color(red: 46/255, green: 95/255, blue: 203/255)
private let atdRecording = Color(red: 206/255, green: 59/255, blue: 54/255)
private let atdSuccess = Color(red: 62/255, green: 157/255, blue: 106/255)

private func phaseColor(_ phase: CaptureActivityAttributes.Phase) -> Color {
    switch phase {
    case .listening:  return atdRecording
    case .processing: return atdAccent
    case .added:      return atdSuccess
    case .ignored:    return atdAccent
    }
}

struct CaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaptureActivityAttributes.self) { context in
            // Écran verrouillé / bannière.
            HStack(spacing: 12) {
                Image(systemName: icon(context.state.phase))
                    .font(.title2).foregroundStyle(phaseColor(context.state.phase))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(context.state.phase)).font(.headline)
                    if !context.state.detail.isEmpty {
                        Text(context.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding()
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: icon(context.state.phase)).foregroundStyle(phaseColor(context.state.phase))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(title(context.state.phase)).font(.caption).bold()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.detail.isEmpty {
                        Text(context.state.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            } compactLeading: {
                Image(systemName: icon(context.state.phase)).foregroundStyle(phaseColor(context.state.phase))
            } compactTrailing: {
                if context.state.phase == .listening {
                    Image(systemName: "waveform").foregroundStyle(atdRecording).symbolEffect(.variableColor.iterative)
                }
            } minimal: {
                Image(systemName: icon(context.state.phase)).foregroundStyle(phaseColor(context.state.phase))
            }
        }
    }

    private func icon(_ phase: CaptureActivityAttributes.Phase) -> String {
        switch phase {
        case .listening:  return "mic.fill"
        case .processing: return "waveform"
        case .added:      return "checkmark.circle.fill"
        case .ignored:    return "xmark.circle"
        }
    }

    private func title(_ phase: CaptureActivityAttributes.Phase) -> String {
        switch phase {
        case .listening:  return "À l'écoute"
        case .processing: return "Traitement"
        case .added:      return "Ajouté"
        case .ignored:    return "Rien à créer"
        }
    }
}
