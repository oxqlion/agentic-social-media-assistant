//
//  SelfSimilarityHighlightDetector.swift
//  app-v1
//
//  On-device port of trial_models/music_highlight_comparison's chosen
//  candidate: Foote's self-similarity novelty method over chroma features.
//  Zero trained parameters — pure signal processing (AVFoundation decode +
//  Accelerate/vDSP), no Core ML model or conversion needed. See that
//  notebook for why this beat MuQ's ~330M-parameter self-similarity and
//  the currently-broken `allin1` on "light and usable locally".
//
//  An `actor` for the same reason CLAPEncoder is one: this app defaults to
//  MainActor isolation, and full-track FFT analysis must not run there.
//

import Foundation

enum SelfSimilarityHighlightDetectorError: Error {
    case emptyTrack
}

actor SelfSimilarityHighlightDetector: TrackHighlightDetecting {
    /// Matches trial_models/music_highlight_comparison's validated constants.
    static let sampleRate: Double = 22_050
    static let minHighlightSeconds: TimeInterval = 10
    static let maxHighlightSeconds: TimeInterval = 30
    static let targetHighlightSeconds: TimeInterval = 30
    static let noveltyRadiusSeconds: Double = 8
    static let minBoundaryGapSeconds: Double = 10

    func detectHighlight(url: URL) async throws -> ClosedRange<TimeInterval> {
        let (samples, duration) = try MLPerfLog.measure("highlight.decode") {
            try FullTrackAudioLoader.load(from: url, targetSampleRate: Self.sampleRate)
        }

        let frames = MLPerfLog.measure("highlight.chroma") {
            ChromaFeatureExtractor.extract(samples: samples, sampleRate: Self.sampleRate)
        }
        guard !frames.chroma.isEmpty else { throw SelfSimilarityHighlightDetectorError.emptyTrack }

        let range = MLPerfLog.measure("highlight.novelty") {
            SelfSimilarityNovelty.pickHighlight(
                frames: frames,
                trackDuration: duration,
                noveltyRadiusSeconds: Self.noveltyRadiusSeconds,
                minBoundaryGapSeconds: Self.minBoundaryGapSeconds,
                minDur: Self.minHighlightSeconds,
                maxDur: Self.maxHighlightSeconds,
                targetDur: Self.targetHighlightSeconds
            )
        }
        MLPerfLog.info("highlight \(range.lowerBound)-\(range.upperBound) for \(url.lastPathComponent)")
        return range
    }
}
