//
//  TrackHighlightDetecting.swift
//  app-v1
//
//  The seam between "however we find a track's highlight/chorus" and the
//  rest of the pipeline — same shape as MusicQueryGenerating. Swapping the
//  self-similarity DSP approach for a trained model later means
//  implementing this protocol, not touching MusicRecommenderAgent.
//

import Foundation

protocol TrackHighlightDetecting: Sendable {
    /// Locates the most-repeated, highest-energy section of the full track
    /// at `url` (typically its chorus/hook) and returns its `[start, end]`
    /// window in seconds. Unlike CLAPEncoder's fixed 10s analyzed window,
    /// this decodes the *entire* file, since finding repeated structure
    /// needs the whole song.
    func detectHighlight(url: URL) async throws -> ClosedRange<TimeInterval>
}
