//
//  CLAPEncoder.swift
//  app-v1
//
//  Owns everything CLAP-specific: model loading, tokenization, and
//  inference for both the audio and text towers. Nothing outside this file
//  knows the model input/output names or that CLAP outputs are already
//  L2-normalized.
//
//  An `actor` so it never inherits this app's `MainActor` default
//  isolation — Core ML inference must not run on the main thread.
//

import CoreAI
import CoreML
import Foundation

enum CLAPEncoderError: Error {
    case missingOutput(String)
}

actor CLAPEncoder {
    static let shared = CLAPEncoder()

    /// The exported audio encoder's only input shape: 10.0s of mono audio
    /// at 48kHz. See AudioWaveformLoader, which produces exactly this many
    /// samples from a local audio file.
    static let sampleRate = 48_000
    static let waveformSampleCount = sampleRate * 10 // 480_000

    private var audioModel: MLModel?
    private var textModel: MLModel?
    private var audioFunction: InferenceFunction?
    private var textFunction: InferenceFunction?
    private var tokenizer: ClapTokenizer?

    private init() {}

    func encodeAudio(_ waveform: [Float]) async throws -> [Float] {
        precondition(
            waveform.count == Self.waveformSampleCount,
            "waveform must be exactly \(Self.waveformSampleCount) samples (10.0s @ \(Self.sampleRate)Hz)"
        )
        if OS27Models.useCoreAI { return try await encodeAudioCoreAI(waveform) }
        let model = try await loadAudioModel()

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "waveform": MLFeatureValue(multiArray: try MLMultiArray.float32(
                shape: [1, Self.waveformSampleCount], values: waveform
            ))
        ])

        let output = try await MLPerfLog.measure("clap.audio.inference") {
            try await model.prediction(from: input)
        }

        guard let embeds = output.featureValue(for: "audio_embeds")?.multiArrayValue else {
            throw CLAPEncoderError.missingOutput("audio_embeds")
        }
        let embedding = embeds.toFloatArray()
        MLPerfLog.info("clap.audio embedding dim=\(embedding.count)")
        return embedding
    }

    func encodeText(_ text: String) async throws -> [Float] {
        if OS27Models.useCoreAI { return try await encodeTextCoreAI(text) }
        let model = try await loadTextModel()
        var tokenizer = try loadTokenizer()

        let encoded = MLPerfLog.measure("clap.text.tokenize") {
            tokenizer.encode(text)
        }
        self.tokenizer = tokenizer

        let inputIds = try MLMultiArray.int32(shape: [1, ClapTokenizer.sequenceLength], values: encoded.inputIds)
        let attentionMask = try MLMultiArray.int32(
            shape: [1, ClapTokenizer.sequenceLength], values: encoded.attentionMask
        )
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
        ])

        let output = try await MLPerfLog.measure("clap.text.inference") {
            try await model.prediction(from: input)
        }

        guard let embeds = output.featureValue(for: "text_embeds")?.multiArrayValue else {
            throw CLAPEncoderError.missingOutput("text_embeds")
        }
        let embedding = embeds.toFloatArray()
        MLPerfLog.info("clap.text embedding dim=\(embedding.count)")
        return embedding
    }

    /// Releases both underlying models. CLAP's text encoder alone is
    /// ~480MB resident (see trial_models/export_for_ios/export_clap.ipynb's
    /// "Quantization status" note) — call once indexing/recommending is
    /// done so it's never held alongside CLIP/Florence.
    func unload() {
        audioModel = nil
        textModel = nil
        audioFunction = nil
        textFunction = nil
    }

    private func encodeAudioCoreAI(_ waveform: [Float]) async throws -> [Float] {
        let function = try await loadAudioFunction()
        let input = NDArray(scalars: waveform, shape: [1, Self.waveformSampleCount])

        let embedding: [Float] = try await MLPerfLog.measure("clap.audio.inference") {
            var outputs = try await function.run(inputs: ["waveform": input])
            guard let value = outputs.remove("audio_embeds"), let array = try await value.ndArray else {
                throw CLAPEncoderError.missingOutput("audio_embeds")
            }
            return array.toFloatArray()
        }
        MLPerfLog.info("clap.audio (Core AI) embedding dim=\(embedding.count)")
        return embedding
    }

    private func encodeTextCoreAI(_ text: String) async throws -> [Float] {
        let function = try await loadTextFunction()
        var tokenizer = try loadTokenizer()

        let encoded = MLPerfLog.measure("clap.text.tokenize") {
            tokenizer.encode(text)
        }
        self.tokenizer = tokenizer

        let shape = [1, ClapTokenizer.sequenceLength]
        let inputs: [String: NDArray] = [
            "input_ids": NDArray(scalars: encoded.inputIds, shape: shape),
            "attention_mask": NDArray(scalars: encoded.attentionMask, shape: shape),
        ]

        let embedding: [Float] = try await MLPerfLog.measure("clap.text.inference") {
            var outputs = try await function.run(inputs: inputs)
            guard let value = outputs.remove("text_embeds"), let array = try await value.ndArray else {
                throw CLAPEncoderError.missingOutput("text_embeds")
            }
            return array.toFloatArray()
        }
        MLPerfLog.info("clap.text (Core AI) embedding dim=\(embedding.count)")
        return embedding
    }

    private func loadAudioFunction() async throws -> InferenceFunction {
        if let audioFunction { return audioFunction }
        let function = try await CoreAIModelLoader.load("ClapAudioEncoder")
        audioFunction = function
        return function
    }

    private func loadTextFunction() async throws -> InferenceFunction {
        if let textFunction { return textFunction }
        let function = try await CoreAIModelLoader.load("ClapTextEncoder")
        textFunction = function
        return function
    }

    private func loadAudioModel() async throws -> MLModel {
        if let audioModel { return audioModel }
        let model = try await CoreMLModelLoader.load("ClapAudioEncoder")
        audioModel = model
        return model
    }

    private func loadTextModel() async throws -> MLModel {
        if let textModel { return textModel }
        let model = try await CoreMLModelLoader.load("ClapTextEncoder")
        textModel = model
        return model
    }

    private func loadTokenizer() throws -> ClapTokenizer {
        if let tokenizer { return tokenizer }
        let loaded = try ClapTokenizer()
        tokenizer = loaded
        return loaded
    }
}

/// Narrow protocol the retrieval layer depends on instead of `CLAPEncoder`
/// directly, so retrieval stays swappable (and fakeable in tests) without
/// touching CLAP internals.
protocol CLAPTextEmbedding: Sendable {
    func encodeText(_ text: String) async throws -> [Float]
}

extension CLAPEncoder: CLAPTextEmbedding {}
