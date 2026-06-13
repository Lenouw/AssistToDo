//
//  CaptureControl.swift
//  AssistToDoWidget
//
//  Contrôle du Centre de contrôle (iOS 18) : un tap lance la capture vocale via RecordVoiceIntent.
//  Peut aussi être mappé sur le bouton Action et l'écran verrouillé.
//

import WidgetKit
import SwiftUI
import AppIntents

struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.assisttodo.capture.control") {
            ControlWidgetButton(action: RecordVoiceIntent()) {
                Label("Note vocale", systemImage: "mic.fill")
            }
        }
        .displayName("Note vocale AssistToDo")
        .description("Lance une capture vocale dans AssistToDo.")
    }
}
