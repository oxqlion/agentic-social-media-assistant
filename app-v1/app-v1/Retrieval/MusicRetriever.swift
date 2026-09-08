//
//  MusicRetriever.swift
//  app-v1
//
//  Ranks the local music index against a text query. Depends on the
//  `CLAPTextEmbedding` protocol rather than `CLAPEncoder` directly, so this
//  layer is replaceable without CLAP knowing it exists — same shape as
//  ImageRetriever.
//

import Foundation

struct MusicRetriever {
    private let textEmbedding: CLAPTextEmbedding
    private let store: MusicEmbeddingStore

    init(textEmbedding: CLAPTextEmbedding = CLAPEncoder.shared, store: MusicEmbeddingStore = .shared) {
        self.textEmbedding = textEmbedding
        self.store = store
    }

    /// `MusicRetriever.search(query: "a warm acoustic tune", topK: 1)`
    ///
    /// Unlike `ImageRetriever`, there's no per-flow `candidates` list —
    /// the music index isn't scoped to a single flow's picks, it's just
    /// "whatever's on the device", kept current by `MusicIndexer`.
    func search(query: String, topK: Int) async throws -> [ScoredTrack] {
        let queryEmbedding = try await MLPerfLog.measure("music.retrieval.textEmbed") {
            try await textEmbedding.encodeText(query)
        }

        let tracks = try await store.allTracks()
        guard !tracks.isEmpty else { return [] }

        let ranked = MLPerfLog.measure("music.retrieval.rank") {
            tracks
                .map { ScoredTrack(track: $0, score: cosineSimilarity(queryEmbedding, $0.embedding)) }
                .sorted { $0.score > $1.score }
        }
        return Array(ranked.prefix(topK))
    }
}
