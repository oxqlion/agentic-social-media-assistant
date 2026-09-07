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

    func run(query: String, topK: Int) async throws -> Result {
        let refinedQuery = await MLPerfLog.measure("agent.query.refine") {
            await refiner.refine(query)
        }
        let images = try await retriever.search(query: refinedQuery, topK: topK)
        return Result(refinedQuery: refinedQuery, images: images)
    }
}
