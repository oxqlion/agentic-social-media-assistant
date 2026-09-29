//
//  FoundationModelMusicQueryGenerator.swift
//  app-v1
//
//  Uses Apple's on-device Foundation Models framework (Apple Intelligence)
//  to turn a post's visual observations + caption into a short,
//  CLAP-friendly music-mood phrase. Fully on-device — no network call is
//  possible through this API. Falls back to the raw context whenever the
//  system model is unavailable, so callers never need to special-case
//  availability themselves — same shape as FoundationModelQueryRefiner.
//

import Foundation
import FoundationModels

struct FoundationModelMusicQueryGenerator: MusicQueryGenerating {
    /// Lets the model look up fuller music preferences on demand.
    let preferencesTool = GetUserPreferencesTool()

    fileprivate static let baseInstructions = """
    You suggest background music for a social media post. Given a visual \
    description of the photos and the post's caption, reply with a short \
    phrase describing the mood, genre, and instrumentation of a fitting \
    track, in the style "a warm, nostalgic acoustic tune" or "a \
    high-energy electronic dance track". Reply with only that phrase and \
    nothing else.
    """

    func generateQuery(observations: String, caption: String, preferenceContext: String) async -> String {
        let context = [observations, caption]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !context.isEmpty else { return context }

        guard case .available = SystemLanguageModel.default.availability else {
            MLPerfLog.info("foundation model unavailable, using raw context for music query")
            return context
        }

        do {
            let session = LanguageModelSession(
                dynamicInstructions: MusicQueryInstructions(preferenceContext: preferenceContext, tool: preferencesTool)
            )
            let response = try await MLPerfLog.measure("agent.music.generate") {
                try await session.respond(to: context)
            }
            let generated = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return generated.isEmpty ? context : generated
        } catch {
            MLPerfLog.info("music query generation failed, using raw context: \(error)")
            return context
        }
    }
}

/// Base instructions + learned music taste + an on-demand preferences tool,
/// composed as OS27 Dynamic Instructions.
private struct MusicQueryInstructions: DynamicInstructions {
    let preferenceContext: String
    let tool: GetUserPreferencesTool

    var body: some DynamicInstructions {
        Instructions { FoundationModelMusicQueryGenerator.baseInstructions }
        PreferenceInstructions(
            facts: preferenceContext,
            lead: "This user's music taste from past posts (follow loosely):"
        )
        tool
    }
}
