//
//  CLIPEncoder.swift
//  app-v1
//
//  Owns everything CLIP-specific: model loading, UIImage preprocessing,
//  tokenization, and inference for both the image and text towers. Nothing
//  outside this file knows the model input/output names, the (frozen-at-3)
//  text batch size, or that CLIP outputs are already L2-normalized.
//
//  An `actor` so it never inherits this app's `MainActor` default
//  isolation — Core ML inference must not run on the main thread.
//

import CoreML
import UIKit

enum CLIPEncoderError: Error {
    case missingImageConstraint
    case missingOutput(String)
}

actor CLIPEncoder {
    static let shared = CLIPEncoder()

    /// The text encoder's exported batch dimension is frozen at 3 (it was
    /// traced on a 3-sentence sample batch). A single query is tiled across
    /// all three rows and row 0 is read back.
    private static let textBatchSize = 3

    private var imageModel: MLModel?
    private var textModel: MLModel?
    private var tokenizer: CLIPTokenizer?

    private init() {}

    func encodeImage(_ image: UIImage) async throws -> [Float] {
        let model = try await loadImageModel()

        guard let constraint = model.modelDescription.inputDescriptionsByName["pixel_values"]?.imageConstraint else {
            throw CLIPEncoderError.missingImageConstraint
        }

        let pixelBuffer = try ImagePreprocessor.makePixelBuffer(
            from: image, constraint: constraint, mode: .aspectFillCenterCrop
        )
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "pixel_values": MLFeatureValue(pixelBuffer: pixelBuffer)
        ])

        let output = try await MLPerfLog.measure("clip.image.inference") {
            try await model.prediction(from: input)
        }

        guard let embeds = output.featureValue(for: "image_embeds")?.multiArrayValue else {
            throw CLIPEncoderError.missingOutput("image_embeds")
        }
        let embedding = embeds.toFloatArray()
        MLPerfLog.info("clip.image embedding dim=\(embedding.count)")
        return embedding
    }

    func encodeText(_ text: String) async throws -> [Float] {
        let model = try await loadTextModel()
        var tokenizer = try loadTokenizer()

        let encoded = MLPerfLog.measure("clip.text.tokenize") {
            tokenizer.encode(text)
        }
        self.tokenizer = tokenizer

        var idsBatch = [Int32](repeating: 0, count: CLIPTokenizer.sequenceLength * Self.textBatchSize)
        var maskBatch = [Int32](repeating: 0, count: CLIPTokenizer.sequenceLength * Self.textBatchSize)
        for row in 0..<Self.textBatchSize {
            let base = row * CLIPTokenizer.sequenceLength
            for i in 0..<CLIPTokenizer.sequenceLength {
                idsBatch[base + i] = encoded.inputIds[i]
                maskBatch[base + i] = encoded.attentionMask[i]
            }
        }

        let inputIds = try MLMultiArray.int32(
            shape: [Self.textBatchSize, CLIPTokenizer.sequenceLength], values: idsBatch
        )
        let attentionMask = try MLMultiArray.int32(
            shape: [Self.textBatchSize, CLIPTokenizer.sequenceLength], values: maskBatch
        )
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
        ])

        let output = try await MLPerfLog.measure("clip.text.inference") {
            try await model.prediction(from: input)
        }

        guard let embeds = output.featureValue(for: "text_embeds")?.multiArrayValue else {
            throw CLIPEncoderError.missingOutput("text_embeds")
        }
        let flattened = embeds.toFloatArray()
        let embeddingDim = embeds.shape.last!.intValue
        let embedding = Array(flattened.prefix(embeddingDim)) // row 0
        MLPerfLog.info("clip.text embedding dim=\(embedding.count)")
        return embedding
    }

    /// Releases both underlying models. Call between indexing passes so
    /// CLIP and Florence never both hold ~400+ MB of weights resident at
    /// the same time.
    func unload() {
        imageModel = nil
        textModel = nil
    }

    private func loadImageModel() async throws -> MLModel {
        if let imageModel { return imageModel }
        let model = try await CoreMLModelLoader.load("CLIPImageEncoder")
        imageModel = model
        return model
    }

    private func loadTextModel() async throws -> MLModel {
        if let textModel { return textModel }
        let model = try await CoreMLModelLoader.load("CLIPTextEncoder")
        textModel = model
        return model
    }

    private func loadTokenizer() throws -> CLIPTokenizer {
        if let tokenizer { return tokenizer }
        let loaded = try CLIPTokenizer()
        tokenizer = loaded
        return loaded
    }
}

/// Narrow protocol the retrieval layer depends on instead of `CLIPEncoder`
/// directly, so retrieval stays swappable without touching CLIP internals.
protocol CLIPTextEmbedding: Sendable {
    func encodeText(_ text: String) async throws -> [Float]
}

extension CLIPEncoder: CLIPTextEmbedding {}
