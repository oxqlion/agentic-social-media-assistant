//
//  MusicRecommenderAgentTests.swift
//  app-v1Tests
//
//  MusicRecommenderAgent is orchestration only — confirms it passes
//  preferenceContext through to the query generator and handles the
//  empty-query / no-match cases without throwing. Uses a temp-directory
//  MusicEmbeddingStore (same pattern as MusicRetrieverTests) so this never
//  touches the real on-device music library.
//

import Testing
import Foundation
@testable import app_v1

private struct RecordingMusicQueryGenerator: MusicQueryGenerating {
    let query: String
    func generateQuery(observations: String, caption: String, preferenceContext: String) async -> String {
        guard !query.isEmpty else { return query }
        return "\(query)[\(preferenceContext)]"
    }
}

private struct FixedTextEmbedding: CLAPTextEmbedding {
    let vector: [Float]
    func encodeText(_ text: String) async throws -> [Float] { vector }
}

@Suite struct MusicRecommenderAgentTests {
    private func makeTempStore() -> MusicEmbeddingStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicRecommenderAgentTests-\(UUID().uuidString)", isDirectory: true)
        return MusicEmbeddingStore(rootDirectory: root)
    }

    @Test func passesPreferenceContextThroughToTheQueryGenerator() async throws {
        let retriever = MusicRetriever(textEmbedding: FixedTextEmbedding(vector: [1, 0]), store: makeTempStore())
        let agent = MusicRecommenderAgent(
            generator: RecordingMusicQueryGenerator(query: "a warm acoustic tune"),
            retriever: retriever
        )

        let result = try await agent.run(
            observations: "a dog on a beach",
            caption: "Sandy paws",
            preferenceContext: "likes acoustic, avoids electronic"
        )

        #expect(result.query == "a warm acoustic tune[likes acoustic, avoids electronic]")
        // No tracks in the (empty) temp store, so no match — confirms the
        // agent doesn't throw when the preference-biased query has no hit.
        #expect(result.track == nil)
    }

    @Test func emptyQueryYieldsNoTrackWithoutThrowing() async throws {
        let retriever = MusicRetriever(textEmbedding: FixedTextEmbedding(vector: [1, 0]), store: makeTempStore())
        let agent = MusicRecommenderAgent(
            generator: RecordingMusicQueryGenerator(query: ""),
            retriever: retriever
        )

        let result = try await agent.run(observations: "", caption: "", preferenceContext: "")

        #expect(result.query.isEmpty)
        #expect(result.track == nil)
        #expect(result.highlightRange == nil)
    }
}
