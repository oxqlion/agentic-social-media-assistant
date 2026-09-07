//
//  ImageEmbeddingStore.swift
//  app-v1
//
//  Local, persistent store of indexed images (embedding + caption +
//  thumbnail), backed by a JSON manifest and JPEG thumbnails in Application
//  Support. No network, no vector database — this *is* the local index the
//  rest of the plan refers to as "local embedding index". An `actor` so
//  concurrent indexing writes stay serialized without an explicit lock.
//

import Foundation
import UIKit

actor ImageEmbeddingStore {
    static let shared = ImageEmbeddingStore()

    private let directoryURL: URL
    private let manifestURL: URL
    private var images: [IndexedImage] = []
    private var loaded = false

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(rootDirectory: appSupport.appendingPathComponent("ImageIndex", isDirectory: true))
    }

    /// Exposed (rather than purely private) so tests can point the store at
    /// an isolated temporary directory instead of the shared instance.
    init(rootDirectory: URL) {
        directoryURL = rootDirectory
        manifestURL = rootDirectory.appendingPathComponent("manifest.json")
    }

    func allImages() throws -> [IndexedImage] {
        try ensureLoaded()
        return images
    }

    var count: Int {
        get throws {
            try ensureLoaded()
            return images.count
        }
    }

    /// Persists a newly-indexed image and its thumbnail.
    func add(_ image: IndexedImage, thumbnail: UIImage) throws {
        try ensureLoaded()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if let data = thumbnail.jpegData(compressionQuality: 0.8) {
            try data.write(to: directoryURL.appendingPathComponent(image.thumbnailFilename))
        }
        images.append(image)
        try persist()
    }

    func removeAll() throws {
        try FileManager.default.removeItem(at: directoryURL)
        images = []
        loaded = true
    }

    nonisolated func thumbnailURL(for image: IndexedImage) -> URL {
        directoryURL.appendingPathComponent(image.thumbnailFilename)
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        loaded = true
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            images = []
            return
        }
        let data = try Data(contentsOf: manifestURL)
        images = try JSONDecoder().decode([IndexedImage].self, from: data)
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(images)
        try data.write(to: manifestURL, options: .atomic)
    }
}
