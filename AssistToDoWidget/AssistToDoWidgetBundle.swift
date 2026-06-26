//
//  AssistToDoWidgetBundle.swift
//  AssistToDoWidget
//
//  Point d'entrée de l'extension : widget de lancement, Live Activity (Dynamic Island)
//  et contrôle du Centre de contrôle (iOS 18). Tous lancent le même RecordVoiceIntent.
//

import WidgetKit
import SwiftUI

/// Couleurs de marque pour l'extension widget. Source unique côté widget : l'extension ne lie PAS
/// AssistToDoKit, donc on ne peut pas réutiliser Color.atd* de Theme.swift ici. À garder en phase
/// avec Theme.swift (atdAccent 0x2E5FCB · atdRecording 0xCE3B36 · atdSuccess 0x3E9D6A).
enum WidgetBrand {
    static let accent    = Color(red: 46 / 255, green: 95 / 255, blue: 203 / 255)  // 0x2E5FCB
    static let recording = Color(red: 206 / 255, green: 59 / 255, blue: 54 / 255)   // 0xCE3B36
    static let success   = Color(red: 62 / 255, green: 157 / 255, blue: 106 / 255)  // 0x3E9D6A
}

@main
struct AssistToDoWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaptureLaunchWidget()
        CaptureLiveActivity()
        CaptureControl()
    }
}
