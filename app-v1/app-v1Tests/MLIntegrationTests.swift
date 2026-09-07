//
//  MLIntegrationTests.swift
//  app-v1Tests
//
//  End-to-end numerical parity against the Python export notebook's own
//  validated Core ML outputs (export_clip_and_florence2.ipynb, cells 11 and
//  21) — the strongest evidence that preprocessing, tokenization, and
//  postprocessing all match on the real, compiled .mlmodelc models. Loads
//  actual model weights, so this is slow; run explicitly, not as part of
//  routine unit test runs.
//

import Foundation
import Testing
import UIKit
@testable import app_v1

private func loadSampleImage(_ name: String) throws -> UIImage {
    // trial_models/images/ lives outside the app bundle, so reach it via
    // the host filesystem path relative to this test file (same trick the
    // fixture loaders use) rather than treating it as a bundled resource.
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // app-v1Tests
        .deletingLastPathComponent() // app-v1
        .deletingLastPathComponent() // app-v1 (outer)
        .appendingPathComponent("trial_models/images/\(name)")
    let data = try Data(contentsOf: url)
    return try #require(UIImage(data: data))
}

@Suite(.serialized) struct MLIntegrationTests {
    @Test func florenceCaptionMatchesNotebook() async throws {
        let image = try loadSampleImage("IMG_4141.jpg")
        let caption = try await FlorenceCaptioner.shared.caption(image)
        await FlorenceCaptioner.shared.unload()

        #expect(caption == "A table topped with lots of different types of sushi.")
    }

    @Test func clipRetrievalMatchesNotebookRanking() async throws {
        let filenames = ["IMG_4302.jpg", "IMG_4277.JPG", "IMG_4141.jpg"]
        var embeddings: [String: [Float]] = [:]
        for name in filenames {
            let image = try loadSampleImage(name)
            embeddings[name] = try await CLIPEncoder.shared.encodeImage(image)
        }

        let foodQuery = try await CLIPEncoder.shared.encodeText("a photo of food")
        await CLIPEncoder.shared.unload()

        let scores = filenames.map { name in (name, cosineSimilarity(foodQuery, embeddings[name]!)) }
        let ranked = scores.sorted { $0.1 > $1.1 }

        // Notebook cell 11: 'a photo of food' ranks IMG_4141.jpg first at ~0.2556.
        #expect(ranked.first?.0 == "IMG_4141.jpg")
        #expect(abs(ranked.first!.1 - 0.2556) < 0.02)
    }
}
