//
//  UserPreferenceMemory.swift
//  app-v1
//
//  Persistent, long-term memory — small and structured, independent of any
//  individual PostInteraction row. Confidence is a ranking signal (see
//  MemoryManager.getPreferences), not an absolute rule, and decays over
//  time when not reinforced (MemoryManager.decayPreferences).
//

import Foundation
import SwiftData

@Model
final class UserPreferenceMemory {
    /// "\(category)|\(value)" — one row per (category, value) pair, e.g.
    /// "image|selfie". Polarity can flip in place (see MemoryManager); the
    /// identity stays keyed on what the preference is about, not its
    /// current direction.
    @Attribute(.unique) var key: String

    var categoryRaw: String
    var value: String
    var polarityRaw: String
    /// 0...1. Never fully 1.0 — treated as a ranking weight, never an
    /// absolute rule.
    var confidence: Double
    var evidenceCount: Int
    var lastObserved: Date
    var explanation: String?

    var category: PreferenceCategory {
        get { PreferenceCategory(rawValue: categoryRaw) ?? .image }
        set { categoryRaw = newValue.rawValue }
    }

    var polarity: PreferencePolarity {
        get { PreferencePolarity(rawValue: polarityRaw) ?? .prefer }
        set { polarityRaw = newValue.rawValue }
    }

    init(
        key: String,
        category: PreferenceCategory,
        value: String,
        polarity: PreferencePolarity,
        confidence: Double,
        evidenceCount: Int,
        lastObserved: Date,
        explanation: String? = nil
    ) {
        self.key = key
        self.categoryRaw = category.rawValue
        self.value = value
        self.polarityRaw = polarity.rawValue
        self.confidence = confidence
        self.evidenceCount = evidenceCount
        self.lastObserved = lastObserved
        self.explanation = explanation
    }
}
