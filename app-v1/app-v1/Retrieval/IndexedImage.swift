//
//  IndexedImage.swift
//  app-v1
//
//  A single locally-indexed image: its CLIP embedding plus the Florence
//  caption captured once at import time. Knows nothing about Core ML.
//

import Foundation

struct IndexedImage: Codable, Identifiable, Sendable {
    let id: UUID
    let embedding: [Float]
    let caption: String?
    /// Filename of the cached JPEG thumbnail inside ImageEmbeddingStore's
    /// storage directory.
    let thumbnailFilename: String
}

/// An `IndexedImage` scored and ranked against a query.
struct ScoredImage: Identifiable, Sendable {
    let image: IndexedImage
    let score: Float
    var id: UUID { image.id }
}
