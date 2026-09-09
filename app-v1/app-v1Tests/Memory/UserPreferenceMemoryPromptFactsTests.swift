//
//  UserPreferenceMemoryPromptFactsTests.swift
//  app-v1Tests
//

import Testing
import Foundation
@testable import app_v1

@Suite struct UserPreferenceMemoryPromptFactsTests {
    private func preference(value: String, polarity: PreferencePolarity, confidence: Double) -> UserPreferenceMemory {
        UserPreferenceMemory(
            key: "image|\(value)", category: .image, value: value, polarity: polarity,
            confidence: confidence, evidenceCount: 1, lastObserved: .now
        )
    }

    @Test func emptyPreferencesYieldAnEmptyString() {
        #expect([UserPreferenceMemory]().asPromptFacts() == "")
    }

    @Test func formatsAsLikesAndAvoids() {
        let facts = [
            preference(value: "landscape", polarity: .prefer, confidence: 0.9),
            preference(value: "selfie", polarity: .avoid, confidence: 0.8)
        ].asPromptFacts()

        #expect(facts == "likes landscape, avoids selfie")
    }

    @Test func strongestConfidenceComesFirstAndLimitIsRespected() {
        let preferences = [
            preference(value: "a", polarity: .prefer, confidence: 0.2),
            preference(value: "b", polarity: .prefer, confidence: 0.9),
            preference(value: "c", polarity: .prefer, confidence: 0.5)
        ]

        let facts = preferences.asPromptFacts(limit: 2)

        #expect(facts == "likes b, likes c")
    }
}
