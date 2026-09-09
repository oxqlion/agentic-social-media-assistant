//
//  PostInteraction.swift
//  app-v1
//
//  Ephemeral, per-post history — one row per created post. Only ever
//  queried for "today"; MemoryManager deletes rows once their day has
//  passed (see MemoryManager.cleanupExpiredDailyHistory). Never store
//  image/audio bytes here, only the identifiers the retrieval layers
//  already hand back (IndexedImage.id, IndexedTrack.persistentID).
//

import Foundation
import SwiftData

@Model
final class PostInteraction {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    /// `yyyy-MM-dd` in the current calendar/timezone — cheap equality
    /// filter for "today's rows" without a date-range predicate.
    var dayKey: String

    var promptText: String
    var selectedImageIDs: [String]
    var rejectedImageIDs: [String]
    var selectedMusicID: String?
    var rejectedMusicIDs: [String]
    var userFeedback: String?

    /// JSON-encoded [BehavioralSignal]; kept as Data instead of a native
    /// array of a Codable struct to sidestep SwiftData's transformable
    /// handling for custom value types.
    private var signalsData: Data

    var signals: [BehavioralSignal] {
        get { (try? JSONDecoder().decode([BehavioralSignal].self, from: signalsData)) ?? [] }
        set { signalsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date,
        dayKey: String,
        promptText: String,
        selectedImageIDs: [String] = [],
        rejectedImageIDs: [String] = [],
        selectedMusicID: String? = nil,
        rejectedMusicIDs: [String] = [],
        userFeedback: String? = nil,
        signals: [BehavioralSignal] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.dayKey = dayKey
        self.promptText = promptText
        self.selectedImageIDs = selectedImageIDs
        self.rejectedImageIDs = rejectedImageIDs
        self.selectedMusicID = selectedMusicID
        self.rejectedMusicIDs = rejectedMusicIDs
        self.userFeedback = userFeedback
        self.signalsData = (try? JSONEncoder().encode(signals)) ?? Data()
    }
}
