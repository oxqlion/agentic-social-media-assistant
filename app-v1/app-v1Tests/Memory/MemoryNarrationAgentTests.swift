//
//  MemoryNarrationAgentTests.swift
//  app-v1Tests
//
//  MemoryNarrationAgent is orchestration only — these confirm it builds
//  the right plain-fact strings and picks the right fallback text,
//  independent of whatever prose the on-device model would produce. A
//  stub narrator that echoes the facts back lets us assert on content
//  without depending on Apple Intelligence being available in CI.
//

import Testing
import Foundation
@testable import app_v1

private struct StubMemoryNarrator: MemoryNarrating {
    func narrate(from facts: String) async -> String { facts }
}

@Suite struct MemoryNarrationAgentTests {
    private let agent = MemoryNarrationAgent(generator: StubMemoryNarrator())

    // MARK: Preferences

    @Test func emptyPreferencesYieldTheNoPreferencesFallback() async {
        let result = await agent.summarizePreferences([])
        #expect(result == MemoryNarrationAgent.noPreferencesFallback)
    }

    @Test func preferencesAreDescribedByPolarityAndCategory() async {
        let preference = UserPreferenceMemory(
            key: "image|landscape",
            category: .image,
            value: "landscape",
            polarity: .prefer,
            confidence: 0.8,
            evidenceCount: 3,
            lastObserved: .now
        )

        let result = await agent.summarizePreferences([preference])

        #expect(result.contains("landscape"))
        #expect(result.contains("prefers"))
        #expect(result.contains("image"))
    }

    @Test func avoidedPreferencesAreDescribedAsAvoiding() async {
        let preference = UserPreferenceMemory(
            key: "image|selfie",
            category: .image,
            value: "selfie",
            polarity: .avoid,
            confidence: 0.6,
            evidenceCount: 2,
            lastObserved: .now
        )

        let result = await agent.summarizePreferences([preference])

        #expect(result.contains("avoids"))
    }

    // MARK: Today

    @Test func emptyDailySnapshotYieldsTheNoActivityFallback() async {
        let result = await agent.summarizeToday(.empty)
        #expect(result == MemoryNarrationAgent.noDailyActivityFallback)
    }

    @Test func dailySnapshotWithSignalsIsDescribed() async {
        let snapshot = DailyMemorySnapshot(
            interactionCount: 2,
            signals: [
                DailyMemorySnapshot.SignalTally(category: .image, value: "landscape", polarity: .prefer, count: 2)
            ]
        )

        let result = await agent.summarizeToday(snapshot)

        #expect(result.contains("landscape"))
        #expect(result.contains("2"))
    }

    // MARK: Pending post

    @Test func emptySignalsYieldTheNoPendingSignalsFallback() async {
        let result = await agent.summarizePendingPost(signals: [])
        #expect(result == MemoryNarrationAgent.noPendingSignalsFallback)
    }

    @Test func pendingSignalsAreDescribedBySelectionVsPassing() async {
        let signals = [
            BehavioralSignal(category: .image, value: "landscape", polarity: .prefer),
            BehavioralSignal(category: .image, value: "selfie", polarity: .avoid)
        ]

        let result = await agent.summarizePendingPost(signals: signals)

        #expect(result.contains("selected"))
        #expect(result.contains("landscape"))
        #expect(result.contains("passed on"))
        #expect(result.contains("selfie"))
    }
}
