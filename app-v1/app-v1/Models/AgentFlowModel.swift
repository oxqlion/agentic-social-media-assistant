//
//  AgentFlowModel.swift
//  app-v1
//
//  Shared state passed between the flow's screens.
//

import SwiftUI
import PhotosUI
import UIKit

enum FlowStep: Hashable {
    case imageSelector
    case progress
    case result
}

@Observable
final class AgentFlowModel {
    var prompt: String = ""
    var selectedPickerItems: [PhotosPickerItem] = []
    var selectedImages: [UIImage] = []
    /// Case study fixture mode only: source filename of each entry in
    /// `selectedImages` (same order), so the result export can name photos.
    var selectedPhotoNames: [String] = []

    /// Query actually sent to CLIP, after the refinement agent runs.
    var refinedQuery: String = ""
    /// Top-K matches from the local image index, ready for ResultView.
    var retrievalResults: [ScoredImage] = []
    /// Surfaced on ResultView if indexing/retrieval failed.
    var retrievalError: String?
    /// Every photo indexed this flow, before the top-K retrieval filter —
    /// kept so ResultView can tell MemoryManager which candidates were
    /// shown but not selected (`indexedCandidates` minus `retrievalResults`).
    var indexedCandidates: [IndexedImage] = []
    /// Florence's caption(s) for the newly-selected photos, joined for
    /// display in ResultView's Caption card.
    var generatedCaption: String = ""
    /// The Hashtag Agent's final, diversified hashtag list for ResultView's
    /// Hashtags card.
    var hashtags: [String] = []

    /// The music-mood phrase the Music Recommender Agent generated from
    /// this flow's observations + caption, sent to CLAP as the query.
    var musicQuery: String = ""
    /// The top-matching locally-indexed song, ready for ResultView's
    /// Recommended Music card.
    var recommendedTrack: ScoredTrack?
    /// Surfaced on ResultView if music indexing/recommendation failed
    /// (most commonly: Music library access denied).
    var musicError: String?
    /// `recommendedTrack`'s detected highlight/chorus window (see
    /// TrackHighlightDetecting), ready for ResultView's Highlight card.
    /// `nil` if no track was recommended or highlight detection failed —
    /// that's not surfaced as an error, the card just doesn't show.
    var highlightRange: ClosedRange<TimeInterval>?

    func reset() {
        prompt = ""
        selectedPickerItems = []
        selectedImages = []
        selectedPhotoNames = []
        refinedQuery = ""
        retrievalResults = []
        retrievalError = nil
        indexedCandidates = []
        generatedCaption = ""
        hashtags = []
        musicQuery = ""
        recommendedTrack = nil
        musicError = nil
        highlightRange = nil
    }
}
