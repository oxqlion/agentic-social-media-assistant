//
//  ImagePreferenceRankerTests.swift
//  app-v1Tests
//
//  ImagePreferenceRanker is a pure re-ranking function — these confirm it
//  nudges scores by matched caption theme and polarity without needing any
//  CoreML model or SwiftData store.
//

import Testing
import Foundation
@testable import app_v1

@Suite struct ImagePreferenceRankerTests {
    private func image(caption: String?) -> IndexedImage {
        IndexedImage(id: UUID(), embedding: [], caption: caption, thumbnailFilename: "x.jpg")
    }

    private func preference(value: String, polarity: PreferencePolarity, confidence: Double) -> UserPreferenceMemory {
        UserPreferenceMemory(
            key: "image|\(value)",
            category: .image,
            value: value,
            polarity: polarity,
            confidence: confidence,
            evidenceCount: 1,
            lastObserved: .now
        )
    }

    @Test func noPreferencesLeavesOrderAndScoresUnchanged() {
        let results = [
            ScoredImage(image: image(caption: "a landscape"), score: 0.5),
            ScoredImage(image: image(caption: "a selfie"), score: 0.6)
        ]

        let ranked = ImagePreferenceRanker.apply(preferences: [], to: results)

        #expect(ranked.map(\.score) == results.map(\.score))
    }

    @Test func preferredThemeIncreasesScore() {
        let scored = ScoredImage(image: image(caption: "a wide landscape view"), score: 0.5)
        let preferences = [preference(value: "landscape", polarity: .prefer, confidence: 0.8)]

        let ranked = ImagePreferenceRanker.apply(preferences: preferences, to: [scored])

        #expect(ranked.first!.score > 0.5)
    }

    @Test func avoidedThemeDecreasesScore() {
        let scored = ScoredImage(image: image(caption: "a selfie in the mirror"), score: 0.5)
        let preferences = [preference(value: "selfie", polarity: .avoid, confidence: 0.8)]

        let ranked = ImagePreferenceRanker.apply(preferences: preferences, to: [scored])

        #expect(ranked.first!.score < 0.5)
    }

    @Test func aPreferredMatchCanReorderResults() {
        let landscape = ScoredImage(image: image(caption: "a wide landscape view"), score: 0.50)
        let selfie = ScoredImage(image: image(caption: "a selfie in the mirror"), score: 0.52)
        let preferences = [
            preference(value: "landscape", polarity: .prefer, confidence: 0.9),
            preference(value: "selfie", polarity: .avoid, confidence: 0.9)
        ]

        let ranked = ImagePreferenceRanker.apply(preferences: preferences, to: [selfie, landscape])

        #expect(ranked.first?.image.caption == "a wide landscape view")
    }

    @Test func imagesWithNoMatchingThemeAreUnaffected() {
        let scored = ScoredImage(image: image(caption: "a plate of food"), score: 0.5)
        let preferences = [preference(value: "landscape", polarity: .prefer, confidence: 0.9)]

        let ranked = ImagePreferenceRanker.apply(preferences: preferences, to: [scored])

        #expect(ranked.first?.score == 0.5)
    }

    @Test func nonImageCategoryPreferencesAreIgnored() {
        let scored = ScoredImage(image: image(caption: "an acoustic vibe landscape"), score: 0.5)
        let musicPreference = UserPreferenceMemory(
            key: "music|landscape",
            category: .music,
            value: "landscape",
            polarity: .prefer,
            confidence: 0.9,
            evidenceCount: 1,
            lastObserved: .now
        )

        let ranked = ImagePreferenceRanker.apply(preferences: [musicPreference], to: [scored])

        #expect(ranked.first?.score == 0.5)
    }
}
