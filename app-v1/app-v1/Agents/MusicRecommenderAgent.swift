//
//  MusicRecommenderAgent.swift
//  app-v1
//
//  Orchestration only: generate a music query from context, then retrieve,
//  then find the winning track's highlight. No tensor code, no model
//  loading, no audio decoding lives here — that's ML/, Retrieval/, and
//  Audio/'s job. Indexing the on-device library is a separate step
//  (MusicIndexer, run beforehand) so this agent only ever has to rank an
//  already-current index.
//
//      Florence observations + caption -> MusicQueryGenerating -> MusicRetriever
//          -> best match -> TrackHighlightDetecting -> highlight range
//

import Foundation

struct MusicRecommenderAgent {
    let generator: MusicQueryGenerating
    let retriever: MusicRetriever
    let highlightDetector: TrackHighlightDetecting

    init(
        generator: MusicQueryGenerating = FoundationModelMusicQueryGenerator(),
        retriever: MusicRetriever = MusicRetriever(),
        highlightDetector: TrackHighlightDetecting = OS27Models.makeHighlightDetector()
    ) {
        self.generator = generator
        self.retriever = retriever
        self.highlightDetector = highlightDetector
    }

    struct Result {
        let query: String
        let track: ScoredTrack?
        /// The recommended track's `[start, end]` highlight window, or
        /// `nil` if none was found (no match, or highlight detection
        /// failed — e.g. an unreadable file). Never fails the whole agent.
        let highlightRange: ClosedRange<TimeInterval>?
    }

    /// `preferenceContext` (see UserPreferenceMemory.asPromptFacts) nudges
    /// the generated mood query toward this user's learned music
    /// preferences.
    func run(observations: String, caption: String, preferenceContext: String = "") async throws -> Result {
        let query = await MLPerfLog.measure("agent.music.query") {
            await generator.generateQuery(observations: observations, caption: caption, preferenceContext: preferenceContext)
        }
        guard !query.isEmpty else { return Result(query: query, track: nil, highlightRange: nil) }

        let matches = try await retriever.search(query: query, topK: 1)
        guard let track = matches.first else {
            return Result(query: query, track: nil, highlightRange: nil)
        }

        let highlightRange = await findHighlight(for: track.track)
        return Result(query: query, track: track, highlightRange: highlightRange)
    }

    /// Best-effort: a track the on-device library can't currently resolve
    /// to a file (or that fails to decode) just means no highlight card,
    /// not a failed recommendation. In case-study fixture mode, `track`
    /// came from `MusicIndexer.indexFixtures()` and has no real on-device
    /// library entry, so its file is resolved via `CaseStudyFixtures`
    /// instead of `MediaLibraryLookup`.
    private func findHighlight(for track: IndexedTrack) async -> ClosedRange<TimeInterval>? {
        let url = CaseStudyFixtures.isEnabled
            ? CaseStudyFixtures.assetURL(forPersistentID: track.persistentID)
            : MediaLibraryLookup.assetURL(forPersistentID: track.persistentID)
        guard let url else { return nil }
        do {
            return try await MLPerfLog.measure("agent.music.highlight") {
                try await highlightDetector.detectHighlight(url: url)
            }
        } catch {
            MLPerfLog.info("highlight detection failed for \(track.title): \(error)")
            return nil
        }
    }
}
