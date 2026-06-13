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

struct CaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaptureActivityAttributes.self) { context in
            // Écran verrouillé / bannière.
            HStack(spacing: 12) {
                Image(systemName: icon(context.state.phase))
                    .font(.title2).foregroundStyle(.tint)
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
                    Image(systemName: icon(context.state.phase)).foregroundStyle(.tint)
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
                Image(systemName: icon(context.state.phase)).foregroundStyle(.tint)
            } compactTrailing: {
                if context.state.phase == .listening { Image(systemName: "waveform") }
            } minimal: {
                Image(systemName: icon(context.state.phase)).foregroundStyle(.tint)
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
