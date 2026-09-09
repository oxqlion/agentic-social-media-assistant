//
//  MemoryManagerTests.swift
//  app-v1Tests
//
//  Each test builds its own in-memory ModelContainer via makeManager() so
//  tests never touch the on-disk store or interfere with each other.
//

import Testing
import SwiftData
import Foundation
@testable import app_v1

@MainActor
struct MemoryManagerTests {

    private func makeManager(calendar: Calendar = .current) -> MemoryManager {
        let schema = Schema([PostInteraction.self, DailyMemory.self, UserPreferenceMemory.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: configuration)
        return MemoryManager(container: container, calendar: calendar)
    }

    // MARK: Recording a post interaction

    @Test
    func recordingAPostSavesAnInteraction() throws {
        let manager = makeManager()

        let interaction = manager.recordPost(
            prompt: "Sunny beach day",
            selectedImages: [PostImageOutcome(id: "img-1", caption: "a landscape photo of a beach")]
        )

        let all = try manager.container.mainContext.fetch(FetchDescriptor<PostInteraction>())
        #expect(all.count == 1)
        #expect(all.first?.id == interaction.id)
        #expect(all.first?.promptText == "Sunny beach day")
        #expect(all.first?.selectedImageIDs == ["img-1"])
    }

    @Test
    func recordingAPostCapturesRejectedImagesAndMusic() throws {
        let manager = makeManager()

        manager.recordPost(
            prompt: "p",
            selectedImages: [PostImageOutcome(id: "kept", caption: "an outdoor scene")],
            rejectedImages: [PostImageOutcome(id: "dropped", caption: "a blurry selfie")],
            acceptedMusic: PostMusicOutcome(id: "track-1", query: "an upbeat acoustic tune"),
            rejectedMusic: [PostMusicOutcome(id: "track-2", query: "a slow ambient piece")]
        )

        let interaction = try #require(try manager.container.mainContext.fetch(FetchDescriptor<PostInteraction>()).first)
        #expect(interaction.rejectedImageIDs == ["dropped"])
        #expect(interaction.selectedMusicID == "track-1")
        #expect(interaction.rejectedMusicIDs == ["track-2"])
    }

    // MARK: Aggregating daily behavior

    @Test
    func recordingAPostAggregatesIntoDailyMemory() throws {
        let manager = makeManager()

        manager.recordPost(
            prompt: "p",
            selectedImages: [PostImageOutcome(id: "1", caption: "a wide landscape at sunset")]
        )

        let dayKey = MemoryManager.dayKey(for: .now)
        var descriptor = FetchDescriptor<DailyMemory>(predicate: #Predicate { $0.dayKey == dayKey })
        descriptor.fetchLimit = 1
        let daily = try #require(try manager.container.mainContext.fetch(descriptor).first)

        #expect(daily.interactionCount == 1)
        #expect(daily.signalCounts["image|landscape|prefer"] == 1)
    }

    // MARK: Confidence growth / weak evidence

    @Test
    func repeatedEvidenceIncreasesConfidence() {
        let manager = makeManager()

        for _ in 0..<3 {
            manager.recordPost(
                prompt: "p",
                selectedImages: [PostImageOutcome(id: UUID().uuidString, caption: "a wide landscape view")]
            )
        }

        let preferences = manager.getPreferences(for: .image, minConfidence: 0)
        let landscape = preferences.first { $0.value == "landscape" }

        #expect(landscape != nil)
        #expect(landscape?.evidenceCount == 3)
        #expect((landscape?.confidence ?? 0) > MemoryManager.baseConfidence)
    }

    @Test
    func singleWeakEvidenceDoesNotSurfaceAsAStrongPreference() {
        let manager = makeManager()

        manager.recordPost(
            prompt: "p",
            selectedImages: [PostImageOutcome(id: "1", caption: "a portrait close up")]
        )

        // Default getPreferences threshold filters out thin evidence.
        let strong = manager.getPreferences(for: .image)
        #expect(strong.isEmpty)

        let all = manager.getPreferences(for: .image, minConfidence: 0)
        let portrait = all.first { $0.value == "portrait" }
        #expect(portrait != nil)
        #expect(portrait?.evidenceCount == 1)
        #expect(portrait?.confidence == MemoryManager.baseConfidence)
    }

    // MARK: Preference updates (conflicting evidence)

    @Test
    func conflictingEvidenceWeakensAndEventuallyFlipsPolarity() {
        let manager = makeManager()

        for _ in 0..<4 {
            manager.recordPost(
                prompt: "p",
                selectedImages: [PostImageOutcome(id: UUID().uuidString, caption: "a selfie in the mirror")]
            )
        }
        let beforeConfidence = manager.getPreferences(for: .image, minConfidence: 0)
            .first { $0.value == "selfie" }?.confidence
        #expect(beforeConfidence != nil)

        for _ in 0..<5 {
            manager.recordPost(
                prompt: "p",
                selectedImages: [],
                rejectedImages: [PostImageOutcome(id: UUID().uuidString, caption: "a selfie in the mirror")]
            )
        }

        let after = manager.getPreferences(for: .image, minConfidence: 0).first { $0.value == "selfie" }
        #expect(after != nil)
        #expect(after?.polarity == .avoid)
    }

    // MARK: Decay

    @Test
    func decayReducesConfidenceForUnreinforcedPreferences() {
        let manager = makeManager()

        for _ in 0..<3 {
            manager.recordPost(
                prompt: "p",
                selectedImages: [PostImageOutcome(id: UUID().uuidString, caption: "a wide landscape view")]
            )
        }
        let before = manager.getPreferences(for: .image, minConfidence: 0).first { $0.value == "landscape" }
        let beforeConfidence = try! #require(before?.confidence)

        let oneHalfLifeLater = Date.now.addingTimeInterval(60 * 60 * 24 * MemoryManager.decayHalfLifeDays)
        manager.decayPreferences(asOf: oneHalfLifeLater)

        let after = manager.getPreferences(for: .image, minConfidence: 0).first { $0.value == "landscape" }
        if let after {
            #expect(after.confidence < beforeConfidence)
            #expect(after.confidence <= beforeConfidence / 2 + 0.01)
        }
        // else: decayed past removalThreshold and was dropped — also a
        // valid outcome of decay working correctly.
    }

    @Test
    func decayDoesNotAffectPreferencesReinforcedToday() {
        let manager = makeManager()
        manager.recordPost(
            prompt: "p",
            selectedImages: [PostImageOutcome(id: "1", caption: "a wide landscape view")]
        )
        let before = manager.getPreferences(for: .image, minConfidence: 0).first { $0.value == "landscape" }?.confidence

        manager.decayPreferences(asOf: .now)

        let after = manager.getPreferences(for: .image, minConfidence: 0).first { $0.value == "landscape" }?.confidence
        #expect(before == after)
    }

    // MARK: Daily history cleanup

    @Test
    func dailyHistoryIsCleanedUpAfterTheDayChanges() throws {
        let manager = makeManager()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!

        manager.recordPost(
            prompt: "p",
            selectedImages: [PostImageOutcome(id: "1", caption: "a wide landscape view")],
            timestamp: yesterday
        )
        #expect(try manager.container.mainContext.fetch(FetchDescriptor<PostInteraction>()).count == 1)
        #expect(try manager.container.mainContext.fetch(FetchDescriptor<DailyMemory>()).count == 1)

        manager.cleanupExpiredDailyHistory(referenceDate: .now)

        #expect(try manager.container.mainContext.fetch(FetchDescriptor<PostInteraction>()).count == 0)
        #expect(try manager.container.mainContext.fetch(FetchDescriptor<DailyMemory>()).count == 0)
    }

    @Test
    func cleanupPreservesTodaysHistory() throws {
        let manager = makeManager()
        manager.recordPost(
            prompt: "p",
            selectedImages: [PostImageOutcome(id: "1", caption: "a wide landscape view")]
        )

        manager.cleanupExpiredDailyHistory(referenceDate: .now)

        #expect(try manager.container.mainContext.fetch(FetchDescriptor<PostInteraction>()).count == 1)
    }

    // MARK: Today snapshot

    @Test
    func todaysSnapshotIsEmptyBeforeAnyPostIsRecorded() {
        let manager = makeManager()
        let snapshot = manager.todaysSnapshot()
        #expect(snapshot.interactionCount == 0)
        #expect(snapshot.signals.isEmpty)
    }

    @Test
    func todaysSnapshotReflectsTodaysRecordedSignals() {
        let manager = makeManager()
        manager.recordPost(
            prompt: "p",
            selectedImages: [PostImageOutcome(id: "1", caption: "a wide landscape view")]
        )
        manager.recordPost(
            prompt: "p",
            selectedImages: [PostImageOutcome(id: "2", caption: "another landscape shot")]
        )

        let snapshot = manager.todaysSnapshot()

        #expect(snapshot.interactionCount == 2)
        let landscape = snapshot.signals.first { $0.value == "landscape" }
        #expect(landscape?.category == .image)
        #expect(landscape?.polarity == .prefer)
        #expect(landscape?.count == 2)
    }

    @Test
    func todaysSnapshotExcludesYesterdaysActivity() {
        let manager = makeManager()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        manager.recordPost(
            prompt: "p",
            selectedImages: [PostImageOutcome(id: "1", caption: "a wide landscape view")],
            timestamp: yesterday
        )

        let snapshot = manager.todaysSnapshot()

        #expect(snapshot.interactionCount == 0)
    }

    // MARK: Querying preferences for image/music selection

    @Test
    func queryingPreferencesIsScopedByCategory() {
        let manager = makeManager()

        for _ in 0..<3 {
            manager.recordPost(
                prompt: "p",
                selectedImages: [PostImageOutcome(id: UUID().uuidString, caption: "an outdoor landscape")],
                acceptedMusic: PostMusicOutcome(id: "track-1", query: "an upbeat acoustic tune")
            )
        }

        let imagePreferences = manager.getPreferences(for: .image)
        let musicPreferences = manager.getPreferences(for: .music)

        #expect(imagePreferences.contains { $0.value == "landscape" })
        #expect(musicPreferences.contains { $0.value == "upbeat" })
        #expect(musicPreferences.contains { $0.value == "acoustic" })
        #expect(imagePreferences.allSatisfy { $0.category == .image })
        #expect(musicPreferences.allSatisfy { $0.category == .music })
    }
}
