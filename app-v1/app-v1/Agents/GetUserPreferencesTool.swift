//
//  GetUserPreferencesTool.swift
//  app-v1
//
//  A Tool the model can call to look up the user's learned preferences on
//  demand, instead of every prompt carrying them up front. Reads through an
//  injectable provider so tests never touch the real MemoryManager.
//

import Foundation
import FoundationModels

struct GetUserPreferencesTool: Tool {
    let name = "get_user_preferences"
    let description = """
    Look up what this user has learned to like or avoid in past posts, for \
    either their photo themes ("image") or their music taste ("music"). \
    Call it when a more specific personal style hint would improve your answer.
    """

    @Generable
    enum Domain: String {
        case image
        case music
    }

    @Generable
    struct Arguments {
        @Guide(description: "Which preferences to look up: image themes or music taste")
        var domain: Domain
    }

    /// Returns the compact fact list for a domain ("likes acoustic, avoids edm").
    let provider: @Sendable (PreferenceCategory) async -> String

    init(provider: @escaping @Sendable (PreferenceCategory) async -> String = GetUserPreferencesTool.memoryProvider) {
        self.provider = provider
    }

    static let memoryProvider: @Sendable (PreferenceCategory) async -> String = { category in
        await MainActor.run {
            MemoryManager.shared.getPreferences(for: category).asPromptFacts(limit: 10)
        }
    }

    func call(arguments: Arguments) async throws -> String {
        let category: PreferenceCategory = arguments.domain == .music ? .music : .image
        let facts = await provider(category)
        return facts.isEmpty ? "No learned \(arguments.domain.rawValue) preferences yet." : facts
    }
}
