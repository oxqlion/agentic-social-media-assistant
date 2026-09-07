//
//  ImageRetrieverTests.swift
//  app-v1Tests
//
//  Regression test for a bug where "Matching Photos" results included
//  images indexed in a previous session: search() defaulted to ranking
//  against the entire persistent ImageEmbeddingStore, which accumulates
//  across sessions, instead of just the photos picked in the current flow.
//

import Foundation
import Testing
import UIKit
@testable import app_v1

private struct FixedTextEmbedding: CLIPTextEmbedding {
    let vector: [Float]
    func encodeText(_ text: String) async throws -> [Float] { vector }
}

@Suite struct ImageRetrieverTests {
    private func makeTempStore() -> ImageEmbeddingStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageRetrieverTests-\(UUID().uuidString)", isDirectory: true)
        return ImageEmbeddingStore(rootDirectory: root)
    }

    private func makeSolidImage() -> UIImage {
        let size = CGSize(width: 4, height: 4)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.red.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func explicitCandidatesExcludeImagesFromPreviousSessions() async throws {
        let store = makeTempStore()

        // Simulates a photo indexed in an earlier session/flow.
        let staleImage = IndexedImage(id: UUID(), embedding: [1, 0], caption: nil, thumbnailFilename: "stale.jpg")
        try await store.add(staleImage, thumbnail: makeSolidImage())

        // Simulates a photo just indexed in the current flow, never added to the store here.
        let currentImage = IndexedImage(id: UUID(), embedding: [0, 1], caption: nil, thumbnailFilename: "current.jpg")

        let retriever = ImageRetriever(textEmbedding: FixedTextEmbedding(vector: [0, 1]), store: store)
        let results = try await retriever.search(query: "anything", topK: 10, in: [currentImage])

        #expect(results.count == 1)
        #expect(results.first?.image.id == currentImage.id)
    }

    @Test func omittingCandidatesFallsBackToWholeStore() async throws {
        let store = makeTempStore()
        let image = IndexedImage(id: UUID(), embedding: [1, 0], caption: nil, thumbnailFilename: "a.jpg")
        try await store.add(image, thumbnail: makeSolidImage())

        let retriever = ImageRetriever(textEmbedding: FixedTextEmbedding(vector: [1, 0]), store: store)
        let results = try await retriever.search(query: "anything", topK: 10)

        #expect(results.count == 1)
        #expect(results.first?.image.id == image.id)
    }
}
