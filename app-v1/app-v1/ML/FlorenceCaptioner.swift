//
//  FlorenceCaptioner.swift
//  app-v1
//
//  Owns everything Florence-specific: model loading, UIImage preprocessing,
//  and the autoregressive greedy decode loop. FlorenceEncoder has the
//  "<CAPTION>" task prompt frozen in at export time, so there is no text
//  input to build here — only image in, hidden states out, then a decoder
//  loop that turns those hidden states into token ids.
//
//  FlorenceDecoderStep has no KV-cache (documented, deliberate export
//  trade-off), so each generation step recomputes the full decoder over the
//  whole fixed-length buffer. Independent from CLIPEncoder — the two never
//  share model state — and coordinated by ImageIndexer so they don't both
//  hold their (~270MB / ~190MB) weights resident at once.
//
//  An `actor` so it never inherits this app's `MainActor` default
//  isolation — Core ML inference must not run on the main thread.
//

import CoreAI
import CoreML
import UIKit

enum FlorenceCaptionerError: Error {
    case missingImageConstraint
    case missingSequenceConstraint
    case missingOutput(String)
}

actor FlorenceCaptioner {
    static let shared = FlorenceCaptioner()

    private var encoderModel: MLModel?
    private var decoderModel: MLModel?
    private var encoderFunction: InferenceFunction?
    private var decoderFunction: InferenceFunction?
    private var vocabulary: FlorenceVocabulary?

    private init() {}

    func caption(_ image: UIImage) async throws -> String {
        if OS27Models.useCoreAI { return try await captionCoreAI(image) }

        let encoderHiddenStates = try await encodeImage(image)
        let tokens = try await generateTokens(encoderHiddenStates: encoderHiddenStates)
        let vocabulary = try loadVocabulary()
        let caption = vocabulary.decode(tokens)
        MLPerfLog.info("florence caption tokens=\(tokens.count) text=\"\(caption)\"")
        return caption
    }

    /// Releases both underlying models. Call between indexing passes so
    /// Florence and CLIP never both hold ~450+ MB of weights resident at
    /// the same time.
    func unload() {
        encoderModel = nil
        decoderModel = nil
        encoderFunction = nil
        decoderFunction = nil
    }

    // MARK: Core AI path
    //
    // Same algorithm as the Core ML path (encoder once, then a no-KV-cache
    // greedy decode over the whole fixed-length buffer) so the runtime is the
    // only variable. The `.aimodel`s are fp16 with float32/int32 boundaries.

    /// Florence's fixed input side and decoder buffer length (see
    /// trial_models/export_for_ios/export_florence_coreai.py).
    private static let imageSide = 768
    private static let maxCaptionTokens = 40

    private func captionCoreAI(_ image: UIImage) async throws -> String {
        let encoder = try await loadEncoderFunction()
        let decoder = try await loadDecoderFunction()

        let pixels = try ImagePreprocessor.makeRGBTensor(from: image, side: Self.imageSide, mode: .squash)
        let hiddenStates: NDArray = try await MLPerfLog.measure("florence.encoder.inference") {
            var outputs = try await encoder.run(inputs: ["pixel_values": pixels])
            guard let value = outputs.remove("encoder_hidden_states"), let array = try await value.ndArray else {
                throw FlorenceCaptionerError.missingOutput("encoder_hidden_states")
            }
            return array
        }

        let sequenceLength = Self.maxCaptionTokens
        var decoderIds = [Int32](repeating: Int32(FlorenceVocabulary.padToken), count: sequenceLength)
        decoderIds[0] = Int32(FlorenceVocabulary.endOfSequence) // decoder_start_token_id
        var generated: [Int] = [FlorenceVocabulary.endOfSequence]

        for _ in 0..<(sequenceLength - 1) {
            try Task.checkCancellation()

            let inputs: [String: NDArray] = [
                "decoder_input_ids": NDArray(scalars: decoderIds, shape: [1, sequenceLength]),
                "encoder_hidden_states": hiddenStates,
            ]
            let rowIndex = generated.count - 1
            let nextToken: Int = try await MLPerfLog.measure("florence.decoder.step") {
                var outputs = try await decoder.run(inputs: inputs)
                guard let value = outputs.remove("logits"), let logits = try await value.ndArray else {
                    throw FlorenceCaptionerError.missingOutput("logits")
                }
                return logits.argmaxOverLastAxis(rowIndex: rowIndex).token
            }

            generated.append(nextToken)
            if nextToken == FlorenceVocabulary.endOfSequence { break }
            decoderIds[generated.count - 1] = Int32(nextToken)
        }

        let caption = try loadVocabulary().decode(generated)
        MLPerfLog.info("florence (Core AI) caption tokens=\(generated.count) text=\"\(caption)\"")
        return caption
    }

    private func loadEncoderFunction() async throws -> InferenceFunction {
        if let encoderFunction { return encoderFunction }
        let function = try await CoreAIModelLoader.load("FlorenceEncoder")
        encoderFunction = function
        return function
    }

    private func loadDecoderFunction() async throws -> InferenceFunction {
        if let decoderFunction { return decoderFunction }
        let function = try await CoreAIModelLoader.load("FlorenceDecoderStep")
        decoderFunction = function
        return function
    }

    // MARK: Core ML path

    private func encodeImage(_ image: UIImage) async throws -> MLMultiArray {
        let encoder = try await loadEncoder()
        guard let constraint = encoder.modelDescription.inputDescriptionsByName["pixel_values"]?.imageConstraint else {
            throw FlorenceCaptionerError.missingImageConstraint
        }

        let pixelBuffer = try ImagePreprocessor.makePixelBuffer(from: image, constraint: constraint, mode: .squash)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "pixel_values": MLFeatureValue(pixelBuffer: pixelBuffer)
        ])

        let output = try await MLPerfLog.measure("florence.encoder.inference") {
            try await encoder.prediction(from: input)
        }
        guard let hiddenStates = output.featureValue(for: "encoder_hidden_states")?.multiArrayValue else {
            throw FlorenceCaptionerError.missingOutput("encoder_hidden_states")
        }
        return hiddenStates
    }

    private func generateTokens(encoderHiddenStates: MLMultiArray) async throws -> [Int] {
        let decoder = try await loadDecoder()
        guard let sequenceLength = decoder.modelDescription
            .inputDescriptionsByName["decoder_input_ids"]?.multiArrayConstraint?.shape.last?.intValue
        else {
            throw FlorenceCaptionerError.missingSequenceConstraint
        }

        // Real tokens must start at index 0 — the decoder's positional
        // embedding is a baked constant indexed by position, so this
        // buffer cannot be left-padded. Right-padding is safe: the
        // decoder's causal mask is also baked, so position i never
        // attends past i regardless of what garbage sits in later slots.
        var decoderIds = [Int32](repeating: Int32(FlorenceVocabulary.padToken), count: sequenceLength)
        decoderIds[0] = Int32(FlorenceVocabulary.endOfSequence) // decoder_start_token_id
        var generated: [Int] = [FlorenceVocabulary.endOfSequence]

        for _ in 0..<(sequenceLength - 1) {
            try Task.checkCancellation()

            let decoderArray = try MLMultiArray.int32(shape: [1, sequenceLength], values: decoderIds)
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "decoder_input_ids": MLFeatureValue(multiArray: decoderArray),
                "encoder_hidden_states": MLFeatureValue(multiArray: encoderHiddenStates),
            ])

            let output = try await MLPerfLog.measure("florence.decoder.step") {
                try await decoder.prediction(from: input)
            }
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
                throw FlorenceCaptionerError.missingOutput("logits")
            }

            let (nextToken, _) = logits.argmaxOverLastAxis(rowIndex: generated.count - 1)
            generated.append(nextToken)
            if nextToken == FlorenceVocabulary.endOfSequence { break }
            decoderIds[generated.count - 1] = Int32(nextToken)
        }

        return generated
    }

    private func loadEncoder() async throws -> MLModel {
        if let encoderModel { return encoderModel }
        let model = try await CoreMLModelLoader.load("FlorenceEncoder")
        encoderModel = model
        return model
    }

    private func loadDecoder() async throws -> MLModel {
        if let decoderModel { return decoderModel }
        let model = try await CoreMLModelLoader.load("FlorenceDecoderStep")
        decoderModel = model
        return model
    }

    private func loadVocabulary() throws -> FlorenceVocabulary {
        if let vocabulary { return vocabulary }
        let loaded = try FlorenceVocabulary()
        vocabulary = loaded
        return loaded
    }
}
