//
//  HUDView.swift
//  AssistToDo
//
//  HUD de capture façon Wispr Flow : pastille d'état + ondes audio live.
//

import SwiftUI

struct HUDView: View {
    @ObservedObject var audio: AudioCapture
    @ObservedObject var model: CaptureModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.state.color)
                    .frame(width: 10, height: 10)
                Text(model.state.label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Waveform(level: audio.level)
                .frame(height: 38)
        }
        .padding(18)
        .frame(width: 260)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.state.label)
    }
}

/// Ondes centrées (forme de cloche) dont l'amplitude suit le volume vocal.
private struct Waveform: View {
    var level: Float
    private let barCount = 21

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: barHeight(i))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let dist = abs(Double(i) - center) / center      // 0 au centre … 1 aux bords
        let shape = 1 - dist * 0.7                        // cloche
        let base = 4.0
        let amplitude = Double(level) * 34 * shape
        return base + amplitude
    }
}
