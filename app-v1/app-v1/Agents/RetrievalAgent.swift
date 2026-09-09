//
//  RetrievalAgent.swift
//  app-v1
//
//  Orchestration only: refine -> retrieve. No tensor code, no model
//  loading, no preprocessing lives here — that's ML/ and Retrieval/'s job.
//
//      User query -> QueryRefining -> ImageRetriever -> top-K images
//

import Foundation

struct RetrievalAgent {
    let refiner: QueryRefining
    let retriever: ImageRetriever

    init(refiner: QueryRefining = FoundationModelQueryRefiner(), retriever: ImageRetriever = ImageRetriever()) {
        self.refiner = refiner
        self.retriever = retriever
    }

    struct Result {
        let refinedQuery: String
        let images: [ScoredImage]
    }

    /// Pass `candidates` to restrict retrieval to a specific set of images
    /// (e.g. only the photos just indexed in the current flow) instead of
    /// the entire persistent index. Pass `preferences` (UserPreferenceMemory,
    /// category .image) to nudge the ranking toward liked themes and away
    /// from avoided ones — see ImagePreferenceRanker.
    func run(
        query: String,
        topK: Int,
        candidates: [IndexedImage]? = nil,
        preferences: [UserPreferenceMemory] = []
    ) async throws -> Result {
        let refinedQuery = await MLPerfLog.measure("agent.query.refine") {
            await refiner.refine(query)
        }
        let images = try await retriever.search(query: refinedQuery, topK: topK, in: candidates)
        let ranked = ImagePreferenceRanker.apply(preferences: preferences, to: images)
        return Result(refinedQuery: refinedQuery, images: ranked)
    }
}
