//
//  FoundationModelQueryRefiner.swift
//  app-v1
//
//  Uses Apple's on-device Foundation Models framework (Apple Intelligence)
//  to turn a casual user query into CLIP-friendly descriptive text. Fully
//  on-device — no network call is possible through this API. Falls back to
//  the raw query whenever the system model is unavailable (device not
//  eligible, Apple Intelligence off, or the model isn't ready), so callers
//  never need to special-case availability themselves.
//

import Foundation
import FoundationModels

struct FoundationModelQueryRefiner: QueryRefining {
    private static let instructions = """
    You rewrite photo search requests into a short, visually descriptive \
    phrase suitable for an image-retrieval model, in the style "a photo of \
    ...". Reply with only the rewritten phrase and nothing else.
    """

    func refine(_ query: String) async -> String {
        guard case .available = SystemLanguageModel.default.availability else {
            MLPerfLog.info("foundation model unavailable, using raw query")
            return query
        }

        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await MLPerfLog.measure("agent.refine") {
                try await session.respond(to: query)
            }
            let refined = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return refined.isEmpty ? query : refined
        } catch {
            MLPerfLog.info("query refinement failed, using raw query: \(error)")
            return query
        }
    }
}
