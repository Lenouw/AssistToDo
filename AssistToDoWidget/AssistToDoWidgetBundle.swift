//
//  AssistToDoWidgetBundle.swift
//  AssistToDoWidget
//
//  Point d'entrée de l'extension : widget de lancement, Live Activity (Dynamic Island)
//  et contrôle du Centre de contrôle (iOS 18). Tous lancent le même RecordVoiceIntent.
//

import WidgetKit
import SwiftUI

@main
struct AssistToDoWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaptureLaunchWidget()
        CaptureLiveActivity()
        CaptureControl()
    }
}
