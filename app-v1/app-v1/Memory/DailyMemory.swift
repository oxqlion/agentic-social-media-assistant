//
//  DailyMemory.swift
//  app-v1
//
//  Temporary aggregated memory for "today" — a running tally of behavioral
//  signal occurrences so MemoryManager doesn't have to re-scan every
//  PostInteraction row to reconcile against UserPreferenceMemory. One row
//  per calendar day; deleted alongside that day's PostInteraction rows once
//  the day has passed.
//

import Foundation
import SwiftData

@Model
final class DailyMemory {
    @Attribute(.unique) var dayKey: String
    var interactionCount: Int
    var lastUpdated: Date

    /// JSON-encoded [BehavioralSignal.aggregationKey: occurrenceCount] —
    /// the running total for today.
    private var signalCountsData: Data
    /// Snapshot of `signalCounts` as of the last `MemoryManager.processDailyMemory`
    /// run, so reconciliation can apply only the *new* occurrences since
    /// last time instead of re-applying the whole day's total on every
    /// call (which would double-count earlier interactions).
    private var reconciledSignalCountsData: Data

    var signalCounts: [String: Int] {
        get { (try? JSONDecoder().decode([String: Int].self, from: signalCountsData)) ?? [:] }
        set { signalCountsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var reconciledSignalCounts: [String: Int] {
        get { (try? JSONDecoder().decode([String: Int].self, from: reconciledSignalCountsData)) ?? [:] }
        set { reconciledSignalCountsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(dayKey: String, lastUpdated: Date) {
        self.dayKey = dayKey
        self.interactionCount = 0
        self.lastUpdated = lastUpdated
        self.signalCountsData = (try? JSONEncoder().encode([String: Int]())) ?? Data()
        self.reconciledSignalCountsData = (try? JSONEncoder().encode([String: Int]())) ?? Data()
    }

    /// Folds one interaction's extracted signals into today's running tally.
    func record(_ interaction: PostInteraction) {
        var counts = signalCounts
        for signal in interaction.signals {
            counts[signal.aggregationKey, default: 0] += 1
        }
        signalCounts = counts
        interactionCount += 1
        lastUpdated = interaction.timestamp
    }
}
