//
//  MemoryManager.swift
//  app-v1
//
//  Integration point for the persistent preference-memory subsystem. Owns
//  its own SwiftData container (PostInteraction, DailyMemory,
//  UserPreferenceMemory) — separate from any UI-facing persistence, so
//  image/music/caption agents can query it without depending on any view.
//
//      Post created -> recordPost() -> extract signals -> save today's
//      PostInteraction -> fold into DailyMemory -> reconcile against
//      UserPreferenceMemory (confidence up/down/new/removed) -> save
//
//  Preferences are ranking signals, not rules: getPreferences(for:) only
//  returns rows past `strongConfidenceThreshold` by default, and
//  confidence decays over time when a preference stops being reinforced
//  (see decayPreferences).
//

import Foundation
import SwiftData

/// What a post-creation flow actually has on hand about one candidate
/// image/track when it calls `recordPost`. `caption`/`query` are the text
/// BehavioralSignalExtractor runs its keyword heuristics over.
struct PostImageOutcome: Sendable {
    let id: String
    let caption: String?

    init(id: String, caption: String?) {
        self.id = id
        self.caption = caption
    }
}

struct PostMusicOutcome: Sendable {
    let id: String
    let query: String

    init(id: String, query: String) {
        self.id = id
        self.query = query
    }
}

/// A read-only view of today's DailyMemory, decoded for display/narration
/// — never mutated, never persisted on its own.
struct DailyMemorySnapshot: Sendable {
    struct SignalTally: Sendable {
        let category: PreferenceCategory
        let value: String
        let polarity: PreferencePolarity
        let count: Int
    }

    let interactionCount: Int
    /// Highest-occurrence signals first.
    let signals: [SignalTally]

    static let empty = DailyMemorySnapshot(interactionCount: 0, signals: [])
}

@MainActor
final class MemoryManager {
    static let shared = MemoryManager()

    // MARK: Tuning constants

    /// Confidence a brand-new preference starts at on its first evidence.
    static let baseConfidence = 0.2
    /// Confidence added per reinforcing occurrence.
    static let reinforceStep = 0.15
    /// Confidence subtracted per conflicting (opposite-polarity) occurrence.
    static let conflictStep = 0.25
    /// Preferences at or below this confidence are dropped outright.
    static let removalThreshold = 0.05
    /// A preference beaten down below this by conflicting evidence flips
    /// polarity instead of just fading — the opposite behavior is now the
    /// better-supported read of the (category, value) pair.
    static let flipThreshold = 0.1
    /// Confidence is a ranking weight, not a rule — never fully certain.
    static let maxConfidence = 0.95
    /// getPreferences(for:) default cutoff: below this, evidence is too
    /// thin to act as a ranking signal yet.
    static let strongConfidenceThreshold = 0.5
    /// Half-life used by decayPreferences for rows not reinforced today.
    static let decayHalfLifeDays = 14.0

    let container: ModelContainer
    private let calendar: Calendar

    init(container: ModelContainer = MemoryManager.makeDefaultContainer(), calendar: Calendar = .current) {
        self.container = container
        self.calendar = calendar
    }

    nonisolated static func makeDefaultContainer() -> ModelContainer {
        let schema = Schema([PostInteraction.self, DailyMemory.self, UserPreferenceMemory.self])
        let configuration = ModelConfiguration("UserPreferenceMemoryStore", schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Failed to create UserPreferenceMemory ModelContainer: \(error)")
        }
    }

    // MARK: - Recording

    /// Call once per created post. Extracts behavioral signals from the
    /// selected/rejected outcomes, appends today's PostInteraction row,
    /// folds it into DailyMemory, then reconciles DailyMemory's tallies
    /// against UserPreferenceMemory.
    @discardableResult
    func recordPost(
        prompt: String,
        selectedImages: [PostImageOutcome],
        rejectedImages: [PostImageOutcome] = [],
        acceptedMusic: PostMusicOutcome? = nil,
        rejectedMusic: [PostMusicOutcome] = [],
        feedback: String? = nil,
        timestamp: Date = .now
    ) -> PostInteraction {
        let context = container.mainContext
        cleanupExpiredDailyHistory(referenceDate: timestamp)

        var signals = BehavioralSignalExtractor.imageSignals(
            selectedCaptions: selectedImages.compactMap(\.caption),
            rejectedCaptions: rejectedImages.compactMap(\.caption)
        )
        signals += BehavioralSignalExtractor.musicSignals(
            acceptedQuery: acceptedMusic?.query,
            rejectedQueries: rejectedMusic.map(\.query)
        )

        let interaction = PostInteraction(
            timestamp: timestamp,
            dayKey: Self.dayKey(for: timestamp, calendar: calendar),
            promptText: prompt,
            selectedImageIDs: selectedImages.map(\.id),
            rejectedImageIDs: rejectedImages.map(\.id),
            selectedMusicID: acceptedMusic?.id,
            rejectedMusicIDs: rejectedMusic.map(\.id),
            userFeedback: feedback,
            signals: signals
        )
        context.insert(interaction)

        let daily = fetchOrCreateDailyMemory(dayKey: interaction.dayKey, context: context)
        daily.record(interaction)

        try? context.save()

        processDailyMemory(referenceDate: timestamp)

        return interaction
    }

    // MARK: - Querying

    /// Preferences for one category, strongest first. `minConfidence`
    /// defaults to `strongConfidenceThreshold` — callers that want to see
    /// weak/emerging preferences too (e.g. debug UI) can pass `0`.
    func getPreferences(
        for category: PreferenceCategory,
        minConfidence: Double = MemoryManager.strongConfidenceThreshold
    ) -> [UserPreferenceMemory] {
        let categoryRaw = category.rawValue
        let descriptor = FetchDescriptor<UserPreferenceMemory>(
            predicate: #Predicate { $0.categoryRaw == categoryRaw },
            sortBy: [SortDescriptor(\.confidence, order: .reverse)]
        )
        let all = (try? container.mainContext.fetch(descriptor)) ?? []
        return all.filter { $0.confidence >= minConfidence }
    }

    /// A snapshot of today's DailyMemory, for the main page's "today" card.
    /// Returns `.empty` if nothing has been recorded yet today.
    func todaysSnapshot(asOf referenceDate: Date = .now) -> DailyMemorySnapshot {
        let context = container.mainContext
        let dayKey = Self.dayKey(for: referenceDate, calendar: calendar)
        guard let daily = fetchDailyMemory(dayKey: dayKey, context: context) else { return .empty }

        let signals = daily.signalCounts
            .compactMap { aggregationKey, count -> DailyMemorySnapshot.SignalTally? in
                guard let signal = BehavioralSignal.parse(aggregationKey: aggregationKey) else { return nil }
                return DailyMemorySnapshot.SignalTally(
                    category: signal.category, value: signal.value, polarity: signal.polarity, count: count
                )
            }
            .sorted { $0.count > $1.count }

        return DailyMemorySnapshot(interactionCount: daily.interactionCount, signals: signals)
    }

    // MARK: - Daily reconciliation

    /// Folds today's *new* DailyMemory signal occurrences (since the last
    /// call) into UserPreferenceMemory: reinforces matching preferences,
    /// weakens/flips conflicting ones, and creates new low-confidence rows
    /// for signals seen for the first time. Safe/idempotent to call
    /// multiple times for the same day — only the delta against
    /// `DailyMemory.reconciledSignalCounts` is applied each time, so
    /// repeat calls without new interactions in between are no-ops.
    func processDailyMemory(referenceDate: Date = .now) {
        let context = container.mainContext
        let dayKey = Self.dayKey(for: referenceDate, calendar: calendar)
        guard let daily = fetchDailyMemory(dayKey: dayKey, context: context) else { return }

        let current = daily.signalCounts
        var reconciled = daily.reconciledSignalCounts

        for (aggregationKey, currentCount) in current {
            let previousCount = reconciled[aggregationKey, default: 0]
            let delta = currentCount - previousCount
            guard delta > 0, let signal = BehavioralSignal.parse(aggregationKey: aggregationKey) else { continue }
            reconcile(signal: signal, occurrences: delta, referenceDate: referenceDate, context: context)
            reconciled[aggregationKey] = currentCount
        }

        daily.reconciledSignalCounts = reconciled
        try? context.save()
    }

    private func reconcile(signal: BehavioralSignal, occurrences: Int, referenceDate: Date, context: ModelContext) {
        let prefKey = signal.preferenceKey

        if let existing = fetchPreference(key: prefKey, context: context) {
            if existing.polarity == signal.polarity {
                existing.confidence = min(Self.maxConfidence, existing.confidence + Self.reinforceStep * Double(occurrences))
                existing.evidenceCount += occurrences
            } else {
                existing.confidence -= Self.conflictStep * Double(occurrences)
                if existing.confidence <= Self.removalThreshold {
                    context.delete(existing)
                    return
                }
                if existing.confidence < Self.flipThreshold {
                    existing.polarity = signal.polarity
                    existing.confidence = min(Self.maxConfidence, Self.baseConfidence * Double(occurrences))
                    existing.evidenceCount = occurrences
                }
            }
            existing.lastObserved = referenceDate
            existing.explanation = Self.explanation(for: signal, evidenceCount: existing.evidenceCount)
        } else {
            let preference = UserPreferenceMemory(
                key: prefKey,
                category: signal.category,
                value: signal.value,
                polarity: signal.polarity,
                confidence: min(Self.maxConfidence, Self.baseConfidence * Double(occurrences)),
                evidenceCount: occurrences,
                lastObserved: referenceDate,
                explanation: Self.explanation(for: signal, evidenceCount: occurrences)
            )
            context.insert(preference)
        }
    }

    private static func explanation(for signal: BehavioralSignal, evidenceCount: Int) -> String {
        let verb = signal.polarity == .prefer ? "prefers" : "avoids"
        let times = evidenceCount == 1 ? "1 time" : "\(evidenceCount) times"
        return "User \(verb) \(signal.value) (\(signal.category.rawValue)) — observed \(times)."
    }

    // MARK: - Decay

    /// Exponentially decays confidence (half-life `decayHalfLifeDays`) for
    /// every preference not observed today, dropping any that fall to or
    /// below `removalThreshold`. Run automatically once per day boundary
    /// via `cleanupExpiredDailyHistory`; exposed directly for tests/manual
    /// maintenance.
    func decayPreferences(asOf referenceDate: Date = .now) {
        let context = container.mainContext
        let all = (try? context.fetch(FetchDescriptor<UserPreferenceMemory>())) ?? []
        guard !all.isEmpty else { return }

        let decayPerDay = pow(0.5, 1.0 / Self.decayHalfLifeDays)
        for preference in all {
            let daysSince = (referenceDate.timeIntervalSince(preference.lastObserved) / 86_400).rounded(.down)
            guard daysSince >= 1 else { continue }
            preference.confidence *= pow(decayPerDay, daysSince)
            if preference.confidence <= Self.removalThreshold {
                context.delete(preference)
            }
        }
        try? context.save()
    }

    // MARK: - Cleanup

    /// Deletes PostInteraction/DailyMemory rows from any day other than
    /// `referenceDate`'s, then runs decay. Called at the start of every
    /// `recordPost`, so daily history never accumulates beyond "today" —
    /// safe to also call proactively (e.g. on app launch).
    func cleanupExpiredDailyHistory(referenceDate: Date = .now) {
        let context = container.mainContext
        let todayKey = Self.dayKey(for: referenceDate, calendar: calendar)

        let staleInteractions = (try? context.fetch(FetchDescriptor<PostInteraction>()))?
            .filter { $0.dayKey != todayKey } ?? []
        for interaction in staleInteractions {
            context.delete(interaction)
        }

        let staleDailyMemories = (try? context.fetch(FetchDescriptor<DailyMemory>()))?
            .filter { $0.dayKey != todayKey } ?? []
        for daily in staleDailyMemories {
            context.delete(daily)
        }

        try? context.save()
        decayPreferences(asOf: referenceDate)
    }

    // MARK: - Helpers

    private func fetchOrCreateDailyMemory(dayKey: String, context: ModelContext) -> DailyMemory {
        if let existing = fetchDailyMemory(dayKey: dayKey, context: context) {
            return existing
        }
        let created = DailyMemory(dayKey: dayKey, lastUpdated: .now)
        context.insert(created)
        return created
    }

    private func fetchDailyMemory(dayKey: String, context: ModelContext) -> DailyMemory? {
        var descriptor = FetchDescriptor<DailyMemory>(predicate: #Predicate { $0.dayKey == dayKey })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func fetchPreference(key: String, context: ModelContext) -> UserPreferenceMemory? {
        var descriptor = FetchDescriptor<UserPreferenceMemory>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
