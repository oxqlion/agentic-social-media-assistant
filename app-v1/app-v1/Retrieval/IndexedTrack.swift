//
//  IndexedTrack.swift
//  app-v1
//
//  A single locally-indexed song: its CLAP audio embedding plus the
//  metadata needed to show and play it. Knows nothing about Core ML or
//  MediaPlayer.
//

import Foundation

struct IndexedTrack: Codable, Identifiable, Sendable {
    /// `MPMediaItem.persistentID` — stable across app launches for the
    /// same library item, so it's the cache key MusicEmbeddingStore diffs
    /// against instead of re-encoding every song on every scan.
    let persistentID: UInt64
    let embedding: [Float]
    let title: String
    let artist: String?
    let duration: TimeInterval
    /// The `[start, end]` window (in seconds) of the track that was
    /// actually decoded and embedded — see AudioWaveformLoader. Surfaced
    /// in the UI instead of a fake "best segment" claim, since only one
    /// window per track is scored (see notes/music-recommendation-plan.md).
    let analyzedRange: ClosedRange<TimeInterval>

    var id: UInt64 { persistentID }
}

/// An `IndexedTrack` scored and ranked against a query.
struct ScoredTrack: Identifiable, Sendable {
    let track: IndexedTrack
    let score: Float
    var id: UInt64 { track.id }
}
