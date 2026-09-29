//
//  OS27Models.swift
//  app-v1
//
//  The switch between the original hand-built models and their OS27
//  replacements. Both stay in the codebase; these flags pick which one the
//  pipeline uses. Defaults to the OS27 path. Override at runtime with
//  UserDefaults (e.g. launch argument `-os27UseFoundationModelVision NO`).
//
//    Vision: Florence (Core ML)            <-> Foundation Models image prompt
//    Music:  chroma + self-similarity DSP  <-> MusicUnderstandingSession
//

import Foundation

enum OS27Models {
    static let visionKey = "os27UseFoundationModelVision"
    static let musicKey = "os27UseMusicUnderstanding"

    static var useFoundationModelVision: Bool { flag(visionKey) }
    static var useMusicUnderstanding: Bool { flag(musicKey) }

    /// `nil` means "use Florence" — ImageIndexer falls back to its captioner.
    static func makeImageDescriber() -> ImageDescribing? {
        useFoundationModelVision ? FoundationModelImageDescriber() : nil
    }

    static func makeHighlightDetector() -> TrackHighlightDetecting {
        useMusicUnderstanding ? MusicUnderstandingHighlightDetector() : SelfSimilarityHighlightDetector()
    }

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
