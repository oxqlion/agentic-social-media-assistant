//
//  MLDebugHarness.swift
//  app-v1
//
//  Development-time utilities for exercising each ML component in
//  isolation, per the plan's testing requirements:
//    1. Florence on a single UIImage
//    2. CLIP image encoding on a single UIImage
//    3. CLIP text encoding
//    4. cosine similarity between an image and text embedding
//    5. retrieval of top-K local images
//  Debug-only: compiled out of release builds entirely.
//

#if DEBUG
import Foundation
import UIKit

enum MLDebugHarness {
    struct TimedResult<T> {
        let value: T
        let milliseconds: Double
    }

    private static func timed<T>(_ work: () async throws -> T) async rethrows -> TimedResult<T> {
        let start = DispatchTime.now()
        let value = try await work()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        return TimedResult(value: value, milliseconds: ms)
    }

    /// 1. Florence captioning on a single image.
    static func runFlorenceCaption(on image: UIImage) async throws -> TimedResult<String> {
        try await timed { try await FlorenceCaptioner.shared.caption(image) }
    }

    /// 2. CLIP image embedding on a single image.
    static func runCLIPImageEncode(on image: UIImage) async throws -> TimedResult<[Float]> {
        try await timed { try await CLIPEncoder.shared.encodeImage(image) }
    }

    /// 3. CLIP text embedding.
    static func runCLIPTextEncode(_ text: String) async throws -> TimedResult<[Float]> {
        try await timed { try await CLIPEncoder.shared.encodeText(text) }
    }

    /// 4. Cosine similarity between an image and a text embedding.
    static func runImageTextSimilarity(image: UIImage, text: String) async throws -> TimedResult<Float> {
        try await timed {
            async let imageEmbedding = CLIPEncoder.shared.encodeImage(image)
            async let textEmbedding = CLIPEncoder.shared.encodeText(text)
            return try await cosineSimilarity(imageEmbedding, textEmbedding)
        }
    }

    /// 5. Retrieval of top-K local images for a query (skips the agent's
    /// query-refinement step, to isolate CLIP + ranking).
    static func runRetrieval(query: String, topK: Int) async throws -> TimedResult<[ScoredImage]> {
        try await timed { try await ImageRetriever().search(query: query, topK: topK) }
    }
}
#endif
