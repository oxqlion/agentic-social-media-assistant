//
//  FoundationModelMemoryNarrator.swift
//  app-v1
//
//  Uses Apple's on-device Foundation Models framework (Apple Intelligence)
//  to turn plain preference/memory facts into a short, readable paragraph.
//  Fully on-device — no network call is possible through this API. Falls
//  back to the raw facts whenever the system model is unavailable (device
//  not eligible, Apple Intelligence off, or the model isn't ready), so
//  callers never need to special-case availability themselves.
//

import Foundation
import FoundationModels

struct FoundationModelMemoryNarrator: MemoryNarrating {
    private static let instructions = """
    You explain a user's on-device behavioral memory for a social-media \
    app in one short, friendly paragraph (2-4 sentences). You are given \
    plain facts about preferences or recent activity — restate only what's \
    given, never invent details beyond it. Write in second person ("you"), \
    do not use bullet points or lists, and do not mention "confidence \
    scores", "signals", or other technical terms. Reply with only the \
    paragraph and nothing else.
    """

    func narrate(from facts: String) async -> String {
        let trimmed = facts.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return facts }

        guard case .available = SystemLanguageModel.default.availability else {
            MLPerfLog.info("foundation model unavailable, using raw memory facts")
            return facts
        }

        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await MLPerfLog.measure("agent.memory.narrate") {
                try await session.respond(to: trimmed)
            }
            let narrated = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return narrated.isEmpty ? facts : narrated
        } catch {
            MLPerfLog.info("memory narration failed, using raw memory facts: \(error)")
            return facts
        }
    }
}
