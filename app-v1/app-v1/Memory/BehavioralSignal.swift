//
//  BehavioralSignal.swift
//  app-v1
//
//  A single observed behavioral data point (e.g. "user avoided selfies"),
//  extracted from one post interaction. Not persisted on its own — batched
//  into PostInteraction.signals and aggregated into DailyMemory.signalCounts.
//

import Foundation

enum PreferenceCategory: String, Codable, CaseIterable, Sendable {
    case image
    case music
    case caption
    case hashtag
}

enum PreferencePolarity: String, Codable, Sendable {
    case prefer
    case avoid
}

struct BehavioralSignal: Codable, Hashable, Sendable {
    let category: PreferenceCategory
    let value: String
    let polarity: PreferencePolarity

    /// Stable string form used as both the DailyMemory aggregation key and
    /// (with category+value only) the UserPreferenceMemory identity key.
    var aggregationKey: String {
        "\(category.rawValue)|\(value)|\(polarity.rawValue)"
    }

    var preferenceKey: String {
        "\(category.rawValue)|\(value)"
    }

    static func parse(aggregationKey key: String) -> BehavioralSignal? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let category = PreferenceCategory(rawValue: parts[0]),
              let polarity = PreferencePolarity(rawValue: parts[2]) else { return nil }
        return BehavioralSignal(category: category, value: parts[1], polarity: polarity)
    }
}
