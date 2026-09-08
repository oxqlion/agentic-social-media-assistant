//
//  MusicRecommenderAgent.swift
//  app-v1
//
//  Orchestration only: generate a music query from context, then retrieve.
//  No tensor code, no model loading, no audio decoding lives here — that's
//  ML/ and Retrieval/'s job. Indexing the on-device library is a separate
//  step (MusicIndexer, run beforehand) so this agent only ever has to rank
//  an already-current index.
//
//      Florence observations + caption -> MusicQueryGenerating -> MusicRetriever -> best match
//

import Foundation

struct MusicRecommenderAgent {
    let generator: MusicQueryGenerating
    let retriever: MusicRetriever

    init(generator: MusicQueryGenerating = FoundationModelMusicQueryGenerator(), retriever: MusicRetriever = MusicRetriever()) {
        self.generator = generator
        self.retriever = retriever
    }

    struct Result {
        let query: String
        let track: ScoredTrack?
    }

    func run(observations: String, caption: String) async throws -> Result {
        let query = await MLPerfLog.measure("agent.music.query") {
            await generator.generateQuery(observations: observations, caption: caption)
        }
        guard !query.isEmpty else { return Result(query: query, track: nil) }

        let matches = try await retriever.search(query: query, topK: 1)
        return Result(query: query, track: matches.first)
    }
}
