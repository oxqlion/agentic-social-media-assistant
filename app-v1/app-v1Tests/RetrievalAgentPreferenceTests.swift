//
//  RetrievalAgentPreferenceTests.swift
//  app-v1Tests
//
//  Confirms RetrievalAgent actually plumbs its `preferences` parameter
//  through to ImagePreferenceRanker (unit-tested on its own in
//  ImagePreferenceRankerTests) rather than just accepting and ignoring it.
//  Uses a stub CLIPTextEmbedding so no CoreML model is needed — passing
//  `candidates` explicitly means ImageRetriever never touches the real,
//  on-disk ImageEmbeddingStore either.
//

import Testing
import Foundation
@testable import app_v1

private struct IdentityRefiner: QueryRefining {
    func refine(_ query: String) async -> String { query }
}

private struct FixedTextEmbedding: CLIPTextEmbedding {
    let vector: [Float]
    func encodeText(_ text: String) async throws -> [Float] { vector }
}

@Suite struct RetrievalAgentPreferenceTests {
    private func image(caption: String, embedding: [Float]) -> IndexedImage {
        IndexedImage(id: UUID(), embedding: embedding, caption: caption, thumbnailFilename: "x.jpg")
    }

    private func preference(value: String, polarity: PreferencePolarity) -> UserPreferenceMemory {
        UserPreferenceMemory(
            key: "image|\(value)", category: .image, value: value, polarity: polarity,
            confidence: 0.9, evidenceCount: 3, lastObserved: .now
        )
    }

    @Test func preferencesReorderEquallyRelevantCandidates() async throws {
        // Both candidates match the query identically (same embedding as
        // the stubbed query vector), so without preferences their order
        // is a coin flip; with a landscape/selfie preference, landscape
        // must win.
        let sharedEmbedding: [Float] = [1, 0, 0]
        let selfie = image(caption: "a selfie in the mirror", embedding: sharedEmbedding)
        let landscape = image(caption: "a wide landscape view", embedding: sharedEmbedding)

        let agent = RetrievalAgent(
            refiner: IdentityRefiner(),
            retriever: ImageRetriever(textEmbedding: FixedTextEmbedding(vector: sharedEmbedding))
        )
        let preferences = [
            preference(value: "landscape", polarity: .prefer),
            preference(value: "selfie", polarity: .avoid)
        ]

        let result = try await agent.run(
            query: "a moment", topK: 2, candidates: [selfie, landscape], preferences: preferences
        )

        #expect(result.images.first?.image.caption == "a wide landscape view")
    }

    @Test func noPreferencesLeavesPureSimilarityOrder() async throws {
        let strongMatch: [Float] = [1, 0, 0]
        let weakMatch: [Float] = [0, 1, 0]
        let a = image(caption: "a selfie", embedding: strongMatch)
        let b = image(caption: "a landscape", embedding: weakMatch)

        let agent = RetrievalAgent(
            refiner: IdentityRefiner(),
            retriever: ImageRetriever(textEmbedding: FixedTextEmbedding(vector: strongMatch))
        )

        let result = try await agent.run(query: "a moment", topK: 2, candidates: [a, b])

        #expect(result.images.first?.image.caption == "a selfie")
    }
}
