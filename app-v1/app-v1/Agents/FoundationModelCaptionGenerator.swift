//
//  FoundationModelCaptionGenerator.swift
//  app-v1
//
//  Uses Apple's on-device Foundation Models framework (Apple Intelligence)
//  to turn Florence's plain visual observations into a natural, engaging
//  social-media caption. Fully on-device — no network call is possible
//  through this API. Falls back to Florence's raw observations whenever the
//  system model is unavailable (device not eligible, Apple Intelligence
//  off, or the model isn't ready), so callers never need to special-case
//  availability themselves.
//

import Foundation
import FoundationModels

struct FoundationModelCaptionGenerator: CaptionGenerating {
    private static let instructions = """
    You are a social-media copywriter. You receive plain visual \
    observations describing a photo (objects, scenery, setting) produced \
    by an image-understanding model. Rewrite those observations into a \
    short, natural, engaging social-media caption — do not simply \
    describe what's in the image. Capture a mood, feeling, or story a \
    person would want to post alongside the photo, and feel free to use \
    a tasteful emoji or two. Reply with only the caption and nothing else.
    """

    func generate(from observations: String) async -> String {
        let trimmed = observations.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return observations }

        guard case .available = SystemLanguageModel.default.availability else {
            MLPerfLog.info("foundation model unavailable, using raw observations")
            return observations
        }

        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await MLPerfLog.measure("agent.caption.generate") {
                try await session.respond(to: trimmed)
            }
            let caption = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return caption.isEmpty ? observations : caption
        } catch {
            MLPerfLog.info("caption generation failed, using raw observations: \(error)")
            return observations
        }
    }
}
