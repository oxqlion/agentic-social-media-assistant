//
//  ImageIndexer.swift
//  app-v1
//
//  The only place Florence and CLIP are used together: at import time.
//  UIImage -> Florence caption -> CLIP image embedding -> local index.
//  Deliberately processes all images through one model, unloads it, then
//  the other — peak resident weight is ever one model (~270MB Florence
//  encoder+~190MB decoder, or ~170MB CLIP image encoder), not all four at
//  once. Search never touches Florence.
//

import Foundation
import UIKit

struct ImageIndexer {
    enum Stage: Sendable {
        case captioning(completed: Int, total: Int)
        case embedding(completed: Int, total: Int)
    }

    private let captioner: FlorenceCaptioner
    private let encoder: CLIPEncoder
    private let store: ImageEmbeddingStore

    init(
        captioner: FlorenceCaptioner = .shared,
        encoder: CLIPEncoder = .shared,
        store: ImageEmbeddingStore = .shared
    ) {
        self.captioner = captioner
        self.encoder = encoder
        self.store = store
    }

    /// Indexes `images`, returning the freshly-created `IndexedImage`
    /// entries (in the same order as `images`) so callers can surface
    /// their Florence captions immediately, without a separate retrieval
    /// round-trip against the persistent store.
    @discardableResult
    func index(_ images: [UIImage], onProgress: @Sendable (Stage) async -> Void) async throws -> [IndexedImage] {
        var captions = [String?](repeating: nil, count: images.count)
        for (i, image) in images.enumerated() {
            try Task.checkCancellation()
            do {
                captions[i] = try await captioner.caption(image)
            } catch {
                MLPerfLog.info("florence caption failed for image \(i): \(error)")
            }
            await onProgress(.captioning(completed: i + 1, total: images.count))
        }
        await captioner.unload()

        var indexedImages: [IndexedImage] = []
        for (i, image) in images.enumerated() {
            try Task.checkCancellation()
            let embedding = try await encoder.encodeImage(image)
            let id = UUID()
            let indexed = IndexedImage(
                id: id, embedding: embedding, caption: captions[i], thumbnailFilename: "\(id.uuidString).jpg"
            )
            try await store.add(indexed, thumbnail: image)
            indexedImages.append(indexed)
            await onProgress(.embedding(completed: i + 1, total: images.count))
        }
        await encoder.unload()
        return indexedImages
    }
}
