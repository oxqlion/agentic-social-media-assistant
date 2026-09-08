//
//  MusicRetrieverTests.swift
//  app-v1Tests
//
//  Ranking correctness against a fake text embedder, isolated from CLAP
//  itself — same shape as ImageRetrieverTests.
//

import Foundation
import Testing
@testable import app_v1

private struct FixedTextEmbedding: CLAPTextEmbedding {
    let vector: [Float]
    func encodeText(_ text: String) async throws -> [Float] { vector }
}

@Suite struct MusicRetrieverTests {
    private func makeTempStore() -> MusicEmbeddingStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicRetrieverTests-\(UUID().uuidString)", isDirectory: true)
        return MusicEmbeddingStore(rootDirectory: root)
    }

    private func makeTrack(id: UInt64, embedding: [Float]) -> IndexedTrack {
        IndexedTrack(
            persistentID: id, embedding: embedding, title: "Song \(id)", artist: nil,
            duration: 180, analyzedRange: 45...55
        )
    }

    @Test func ranksByCosineSimilarityDescending() async throws {
        let store = makeTempStore()
        try await store.add(makeTrack(id: 1, embedding: [1, 0]))
        try await store.add(makeTrack(id: 2, embedding: [0, 1]))
        try await store.add(makeTrack(id: 3, embedding: [0.7, 0.7]))

        let retriever = MusicRetriever(textEmbedding: FixedTextEmbedding(vector: [1, 0]), store: store)
        let results = try await retriever.search(query: "anything", topK: 10)

        #expect(results.map(\.track.persistentID) == [1, 3, 2])
    }

    @Test func respectsTopK() async throws {
        let store = makeTempStore()
        try await store.add(makeTrack(id: 1, embedding: [1, 0]))
        try await store.add(makeTrack(id: 2, embedding: [0.9, 0.1]))
        try await store.add(makeTrack(id: 3, embedding: [0, 1]))

        let retriever = MusicRetriever(textEmbedding: FixedTextEmbedding(vector: [1, 0]), store: store)
        let results = try await retriever.search(query: "anything", topK: 1)

        #expect(results.count == 1)
        #expect(results.first?.track.persistentID == 1)
    }

    @Test func emptyStoreReturnsNoResults() async throws {
        let store = makeTempStore()
        let retriever = MusicRetriever(textEmbedding: FixedTextEmbedding(vector: [1, 0]), store: store)
        let results = try await retriever.search(query: "anything", topK: 10)
        #expect(results.isEmpty)
    }
}
