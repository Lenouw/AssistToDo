//
//  AudioSamples16k.swift
//  AssistToDoKit
//
//  Décode un fichier audio (.caf enregistré au sample rate natif, ex 48 kHz mono) en un tableau
//  de Float 16 kHz mono, format attendu par whisper.cpp (qui ne rééchantillonne pas lui-même,
//  contrairement à WhisperKit). Utilise AVAudioConverter.
//

import Foundation
import AVFoundation

enum AudioSamples16k {
    /// Charge `path` et renvoie les échantillons en 16 kHz mono Float. `nil` si lecture impossible.
    static func load(path: String) -> [Float]? {
        let url = URL(fileURLWithPath: path)
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let srcFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else { return nil }
        do { try file.read(into: srcBuffer) } catch { return nil }

        // Cible : 16 kHz, mono, Float32 non entrelacé.
        guard let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                            channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else { return nil }

        let ratio = 16_000.0 / srcFormat.sampleRate
        let dstCapacity = AVAudioFrameCount(Double(frameCount) * ratio + 4096)
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: dstCapacity) else { return nil }

        var fed = false
        var convError: NSError?
        let status = converter.convert(to: dstBuffer, error: &convError) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true; outStatus.pointee = .haveData; return srcBuffer
        }
        guard status != .error, convError == nil,
              let channel = dstBuffer.floatChannelData else { return nil }

        let n = Int(dstBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channel[0], count: n))
    }
}
