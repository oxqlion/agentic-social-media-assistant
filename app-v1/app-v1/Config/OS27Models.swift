//
//  OS27Models.swift
//  app-v1
//
//  The switch between the original hand-built models and their OS27
//  replacements. Both stay in the codebase; these flags pick which one the
//  pipeline uses. Defaults to the ORIGINAL local-model path (Florence + DSP) in this
//  coreai build, keeping Foundation Models only for the text agents. Override at
//  runtime with UserDefaults (e.g. launch argument `-os27UseFoundationModelVision YES`).
//
//    Vision: Florence (Core ML)            <-> Foundation Models image prompt
//    Music:  chroma + self-similarity DSP  <-> MusicUnderstandingSession
//    Runtime: Core ML .mlpackage           <-> Core AI .aimodel (`-os27UseCoreAI YES`)
//

import Foundation

enum OS27Models {
    static let visionKey = "os27UseFoundationModelVision"
    static let musicKey = "os27UseMusicUnderstanding"
    static let coreAIKey = "os27UseCoreAI"

    static var useFoundationModelVision: Bool { flag(visionKey) }
    static var useMusicUnderstanding: Bool { flag(musicKey) }

    /// Runtime for the local encoders: Core ML (`.mlpackage`) <-> Core AI
    /// (`.aimodel`). Off by default; models are migrated one at a time, so a
    /// model with no `.aimodel` yet always stays on Core ML.
    static var useCoreAI: Bool { flag(coreAIKey) }

    /// `nil` means "use Florence" — ImageIndexer falls back to its captioner.
    static func makeImageDescriber() -> ImageDescribing? {
        useFoundationModelVision ? FoundationModelImageDescriber() : nil
    }

    static func makeHighlightDetector() -> TrackHighlightDetecting {
        useMusicUnderstanding ? MusicUnderstandingHighlightDetector() : SelfSimilarityHighlightDetector()
    }

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? false
    }
}
