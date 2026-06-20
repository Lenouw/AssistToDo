//
//  CaptureLaunchWidget.swift
//  AssistToDoWidget
//
//  Widget écran d'accueil / verrouillé : un tap (Button + AppIntent, iOS 17+) lance la capture.
//

import WidgetKit
import SwiftUI
import AppIntents

struct CaptureEntry: TimelineEntry { let date: Date }

struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry { CaptureEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        completion(Timeline(entries: [CaptureEntry(date: .now)], policy: .never))
    }
}

struct CaptureLaunchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.assisttodo.capture.launch", provider: CaptureProvider()) { _ in
            CaptureWidgetView()
        }
        .configurationDisplayName("Capture AssistToDo")
        .description("Lance une note vocale d'un tap.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct CaptureWidgetView: View {
    private let atdAccent = Color(red: 110/255, green: 86/255, blue: 247/255)
    var body: some View {
        Button(intent: RecordVoiceIntent()) {
            VStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(atdAccent)
                Text("Note").font(.caption.weight(.medium)).foregroundStyle(atdAccent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .containerBackground(atdAccent.opacity(0.16), for: .widget)
    }
}
