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

    /// Query actually sent to CLIP, after the refinement agent runs.
    var refinedQuery: String = ""
    /// Top-K matches from the local image index, ready for ResultView.
    var retrievalResults: [ScoredImage] = []
    /// Surfaced on ResultView if indexing/retrieval failed.
    var retrievalError: String?
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

    func reset() {
        prompt = ""
        selectedPickerItems = []
        selectedImages = []
        refinedQuery = ""
        retrievalResults = []
        retrievalError = nil
        generatedCaption = ""
        hashtags = []
        musicQuery = ""
        recommendedTrack = nil
        musicError = nil
    }
}
