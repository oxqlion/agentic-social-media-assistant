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
    ///
    /// Pass `candidates` to rank a specific set of images (e.g. only the
    /// photos just indexed in the current flow) instead of the entire
    /// persistent index, which accumulates across every past session.
    func search(query: String, topK: Int, in candidates: [IndexedImage]? = nil) async throws -> [ScoredImage] {
        let queryEmbedding = try await MLPerfLog.measure("retrieval.textEmbed") {
            try await textEmbedding.encodeText(query)
        }

        let images: [IndexedImage]
        if let candidates {
            images = candidates
        } else {
            images = try await store.allImages()
        }
        guard !images.isEmpty else { return [] }

        let ranked = MLPerfLog.measure("retrieval.rank") {
            images
                .map { ScoredImage(image: $0, score: cosineSimilarity(queryEmbedding, $0.embedding)) }
                .sorted { $0.score > $1.score }
        }
        return Array(ranked.prefix(topK))
    }
}
