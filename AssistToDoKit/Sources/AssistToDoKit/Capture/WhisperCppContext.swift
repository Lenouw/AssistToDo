//
//  WhisperCppContext.swift
//  AssistToDoKit
//
//  Wrapper bas niveau autour de whisper.cpp (moteur ggml + Metal), remplaçant CoreML/WhisperKit.
//  Chargé par mmap → quasi instantané, aucune compilation ANE. Contrainte whisper.cpp : ne pas
//  accéder au contexte depuis plusieurs threads → on l'isole dans un actor.
//

import Foundation
import whisper

enum WhisperCppError: Error { case initFailed, runFailed }

actor WhisperCppContext {
    private var context: OpaquePointer

    private init(context: OpaquePointer) { self.context = context }
    deinit { whisper_free(context) }

    /// Charge le modèle GGML depuis un `.bin` (mmap). Metal sur device, CPU sur simulateur.
    static func create(modelPath: String) throws -> WhisperCppContext {
        var params = whisper_context_default_params()
        #if targetEnvironment(simulator)
        params.use_gpu = false
        #else
        params.flash_attn = true   // activé par défaut avec Metal
        #endif
        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperCppError.initFailed
        }
        return WhisperCppContext(context: ctx)
    }

    struct Result { let text: String; let avgLogProb: Float }

    /// Transcrit des samples 16 kHz mono Float. `language` ex "fr". Renvoie texte + logprob moyen
    /// par token (pour le garde-fou anti-hallucination, comparable à l'avgLogprob de WhisperKit).
    func transcribe(samples: [Float], language: String) throws -> Result {
        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime   = false
        params.print_progress   = false
        params.print_timestamps = false
        params.print_special    = false
        params.translate        = false
        params.no_context       = true
        params.single_segment   = false
        params.suppress_blank   = true
        params.temperature      = 0
        params.n_threads        = Int32(maxThreads)

        let ok: Bool = language.withCString { lang in
            params.language = lang
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(context, params, buf.baseAddress, Int32(buf.count)) == 0
            }
        }
        guard ok else { throw WhisperCppError.runFailed }

        var text = ""
        var logSum: Double = 0
        var tokenCount = 0
        let nSeg = whisper_full_n_segments(context)
        for s in 0..<nSeg {
            if let c = whisper_full_get_segment_text(context, s) { text += String(cString: c) }
            let nTok = whisper_full_n_tokens(context, s)
            for t in 0..<nTok {
                let p = whisper_full_get_token_p(context, s, t)   // proba 0…1
                if p > 0 { logSum += Double(log(p)); tokenCount += 1 }
            }
        }
        let avg = tokenCount > 0 ? Float(logSum / Double(tokenCount)) : 0
        return Result(text: text.trimmingCharacters(in: .whitespacesAndNewlines), avgLogProb: avg)
    }
}
