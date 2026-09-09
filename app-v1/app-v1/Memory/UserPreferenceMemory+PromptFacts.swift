//
//  UserPreferenceMemory+PromptFacts.swift
//  app-v1
//
//  A short, plain "likes X, avoids Y" phrase for direct injection into an
//  on-device LLM prompt as style guidance — distinct from
//  MemoryNarrationAgent, which turns preferences into user-facing prose.
//

import Foundation

extension Array where Element == UserPreferenceMemory {
    /// The strongest preferences, rendered as a compact fact list (e.g.
    /// "likes landscape, avoids selfie"). Empty if there's nothing to say.
    func asPromptFacts(limit: Int = 5) -> String {
        sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { "\($0.polarity == .prefer ? "likes" : "avoids") \($0.value)" }
            .joined(separator: ", ")
    }
}
