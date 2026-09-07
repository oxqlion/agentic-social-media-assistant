//
//  ImageEmbeddingStoreTests.swift
//  app-v1Tests
//
//  Round-trip persistence, isolated to a temp directory per test so this
//  never touches (or is polluted by) the app's real on-device index.
//

import Testing
import UIKit
@testable import app_v1

@Suite struct ImageEmbeddingStoreTests {
    private func makeTempStore() -> ImageEmbeddingStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageEmbeddingStoreTests-\(UUID().uuidString)", isDirectory: true)
        return ImageEmbeddingStore(rootDirectory: root)
    }

    private func makeSolidImage(color: UIColor = .red, size: CGSize = CGSize(width: 4, height: 4)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func addAndRetrieve() async throws {
        let store = makeTempStore()
        let image = IndexedImage(
            id: UUID(), embedding: [0.1, 0.2, 0.3], caption: "a test image", thumbnailFilename: "a.jpg"
        )
        try await store.add(image, thumbnail: makeSolidImage())

        let all = try await store.allImages()
        #expect(all.count == 1)
        #expect(all.first?.id == image.id)
        #expect(all.first?.caption == "a test image")
        #expect(try await store.count == 1)
    }

    @Test func persistsAcrossInstances() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageEmbeddingStoreTests-\(UUID().uuidString)", isDirectory: true)
        let image = IndexedImage(id: UUID(), embedding: [1, 2, 3], caption: nil, thumbnailFilename: "b.jpg")

        let first = ImageEmbeddingStore(rootDirectory: root)
        try await first.add(image, thumbnail: makeSolidImage())

        let second = ImageEmbeddingStore(rootDirectory: root)
        let reloaded = try await second.allImages()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.embedding == [1, 2, 3])
    }

    @Test func removeAllClearsStore() async throws {
        let store = makeTempStore()
        try await store.add(
            IndexedImage(id: UUID(), embedding: [1], caption: nil, thumbnailFilename: "c.jpg"),
            thumbnail: makeSolidImage()
        )
        try await store.removeAll()
        #expect(try await store.allImages().isEmpty)
    }
}
