//
//  MemoryNarrationAgent.swift
//  app-v1
//
//  Orchestration only: turns memory-subsystem data (UserPreferenceMemory
//  rows, a DailyMemorySnapshot, or a pending post's not-yet-recorded
//  BehavioralSignals) into plain facts, then hands those to MemoryNarrating
//  for prose. No SwiftData, no persistence lives here — that's Memory/'s
//  job.
//
//      UserPreferenceMemory / DailyMemorySnapshot / [BehavioralSignal]
//          -> plain-fact string -> MemoryNarrating -> paragraph
//

import Foundation

struct MemoryNarrationAgent {
    let generator: MemoryNarrating

    init(generator: MemoryNarrating = FoundationModelMemoryNarrator()) {
        self.generator = generator
    }

    static let noPreferencesFallback =
        "Your agents haven't learned any preferences yet — keep creating posts and patterns will start showing up here."
    static let noDailyActivityFallback =
        "No posts yet today — create one and today's activity will start filling in here."
    static let noPendingSignalsFallback =
        "This post doesn't have enough distinct signals for your agents to learn anything from yet."

    /// Long-term memory, for the main page's "what your agents have
    /// learned" card.
    func summarizePreferences(_ preferences: [UserPreferenceMemory]) async -> String {
        guard !preferences.isEmpty else { return Self.noPreferencesFallback }

        let facts = preferences
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
            .map { preference -> String in
                let strength = preference.confidence >= 0.75 ? "strongly" : preference.confidence >= 0.5 ? "moderately" : "mildly"
                let verb = preference.polarity == .prefer ? "prefers" : "avoids"
                let times = preference.evidenceCount == 1 ? "1 time" : "\(preference.evidenceCount) times"
                return "\(strength) \(verb) \(preference.value) (\(preference.category.rawValue), observed \(times))"
            }
            .joined(separator: "; ")

        return await generator.narrate(from: "User preference facts: \(facts).")
    }

    /// Today's ephemeral memory, for the main page's "today" card.
    func summarizeToday(_ daily: DailyMemorySnapshot) async -> String {
        guard daily.interactionCount > 0 else { return Self.noDailyActivityFallback }

        let facts = daily.signals
            .prefix(8)
            .map { tally -> String in
                let verb = tally.polarity == .prefer ? "liked" : "avoided"
                return "\(verb) \(tally.value) (\(tally.category.rawValue)) x\(tally.count)"
            }
            .joined(separator: "; ")
        let postWord = daily.interactionCount == 1 ? "post" : "posts"

        return await generator.narrate(
            from: "Today the user created \(daily.interactionCount) \(postWord). Observed: \(facts.isEmpty ? "nothing distinctive yet" : facts)."
        )
    }

    /// The current, not-yet-recorded post's outcome, for the result page's
    /// "what this post will teach your agents" card.
    func summarizePendingPost(signals: [BehavioralSignal]) async -> String {
        guard !signals.isEmpty else { return Self.noPendingSignalsFallback }

        let facts = signals
            .map { signal -> String in
                let verb = signal.polarity == .prefer ? "selected" : "passed on"
                return "\(verb) \(signal.value) (\(signal.category.rawValue))"
            }
            .joined(separator: "; ")

        return await generator.narrate(from: "This post is about to teach the agents: \(facts).")
    }
}
