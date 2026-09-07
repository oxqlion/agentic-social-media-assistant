//
//  ImageRetriever.swift
//  app-v1
//
//  Ranks the local image index against a text query. Depends on the
//  `CLIPTextEmbedding` protocol rather than `CLIPEncoder` directly, so this
//  layer is replaceable (a different encoder, a different index backend)
//  without CLIP knowing it exists.
//

import Foundation

struct ImageRetriever {
    private let textEmbedding: CLIPTextEmbedding
    private let store: ImageEmbeddingStore

    init(textEmbedding: CLIPTextEmbedding = CLIPEncoder.shared, store: ImageEmbeddingStore = .shared) {
        self.textEmbedding = textEmbedding
        self.store = store
    }

    /// `ImageRetriever.search(query: "pictures of beaches and dogs", topK: 20)`
    func search(query: String, topK: Int) async throws -> [ScoredImage] {
        let queryEmbedding = try await MLPerfLog.measure("retrieval.textEmbed") {
            try await textEmbedding.encodeText(query)
        }

        let images = try await store.allImages()
        guard !images.isEmpty else { return [] }

        let ranked = MLPerfLog.measure("retrieval.rank") {
            images
                .map { ScoredImage(image: $0, score: cosineSimilarity(queryEmbedding, $0.embedding)) }
                .sorted { $0.score > $1.score }
        }
        return Array(ranked.prefix(topK))
    }
}
