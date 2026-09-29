//
//  MusicUnderstandingHighlightDetector.swift
//  app-v1
//
//  OS27 replacement for SelfSimilarityHighlightDetector: asks the
//  MusicUnderstanding framework for the track's structure and pace, then
//  picks the highest-energy section as the highlight.
//
//  `StructureResult.sections` are unlabeled time ranges (no "chorus" tag),
//  so "highlight" = the section with the highest duration-weighted pace,
//  clamped to the same 10–30s window the old detector used.
//

import AVFoundation
import Foundation
import MusicUnderstanding

enum MusicUnderstandingHighlightDetectorError: Error {
    case noSections
}

struct MusicUnderstandingHighlightDetector: TrackHighlightDetecting {
    static let minHighlightSeconds: TimeInterval = 10
    static let maxHighlightSeconds: TimeInterval = 30

    /// A time range in seconds, decoupled from CoreMedia so selection can be
    /// unit-tested without the framework.
    struct Span: Equatable, Sendable {
        let start: TimeInterval
        let end: TimeInterval
        var duration: TimeInterval { max(0, end - start) }
    }

    struct PacedSpan: Equatable, Sendable {
        let span: Span
        let pace: Double
    }

    func detectHighlight(url: URL) async throws -> ClosedRange<TimeInterval> {
        let result = try await MLPerfLog.measure("highlight.musicunderstanding") {
            let session = try await MusicUnderstandingSession(asset: AVURLAsset(url: url))
            return try await session.analyze(for: [.structure, .pace])
        }
        let sections = (result.structure?.sections ?? []).compactMap(Self.span(from:))
        let pace = (result.pace?.ranges ?? []).compactMap { ranged -> PacedSpan? in
            Self.span(from: ranged.range).map { PacedSpan(span: $0, pace: ranged.value) }
        }
        let range = try Self.pickHighlight(sections: sections, pace: pace)
        MLPerfLog.info("highlight \(range.lowerBound)-\(range.upperBound) for \(url.lastPathComponent)")
        return range
    }

    // MARK: - Selection (pure)

    static func pickHighlight(sections: [Span], pace: [PacedSpan]) throws -> ClosedRange<TimeInterval> {
        let usable = sections.filter { $0.duration > 0 }
        guard !usable.isEmpty else { throw MusicUnderstandingHighlightDetectorError.noSections }

        // Highest average pace wins; with no pace data, the longest section.
        let best = usable.max { score($0, pace: pace) < score($1, pace: pace) }!
        return clamp(best)
    }

    /// Duration-weighted mean pace across the pace ranges overlapping `span`.
    /// Falls back to duration when there is no overlap, so it still orders.
    private static func score(_ span: Span, pace: [PacedSpan]) -> Double {
        var weighted = 0.0
        var covered = 0.0
        for p in pace {
            let overlap = min(span.end, p.span.end) - max(span.start, p.span.start)
            guard overlap > 0 else { continue }
            weighted += p.pace * overlap
            covered += overlap
        }
        // Pace is the primary key (scaled up); duration only breaks ties and
        // orders sections when no pace data overlaps.
        return covered > 0 ? weighted / covered * 1_000 + span.duration * 0.001 : span.duration * 0.001
    }

    /// Fits `span` into [min, max] seconds, keeping its start; a section
    /// shorter than the minimum is extended forward.
    private static func clamp(_ span: Span) -> ClosedRange<TimeInterval> {
        let length = min(max(span.duration, minHighlightSeconds), maxHighlightSeconds)
        return span.start...(span.start + length)
    }

    private static func span(from range: CMTimeRange) -> Span? {
        guard range.start.isNumeric, range.duration.isNumeric else { return nil }
        let start = range.start.seconds
        let duration = range.duration.seconds
        guard start.isFinite, duration.isFinite else { return nil }
        return Span(start: start, end: start + duration)
    }
}
