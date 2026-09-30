//
//  CaseStudyResultExport.swift
//  app-v1
//
//  Case study only (fixture mode, see CaseStudyFixtures): serializes what
//  the agent pipeline actually produced — caption, hashtags, photos,
//  music, preference memory — to JSON. ResultView exposes the JSON as
//  hidden accessibility elements, because the UI test runs in its own
//  process and can't read the app's model. CaseStudyPerformanceTests reads
//  those elements and attaches them to the .xcresult;
//  case-study/scripts/extract_outputs.py then copies them into
//  case-study/results/<run>/.
//

import Foundation

/// Everything the flow produced, as of ResultView appearing (before "Post").
struct CaseStudyResultSnapshot: Codable {
    struct Photo: Codable {
        /// Fixture filename (stable across runs/apps).
        let file: String
        /// Per-photo caption/observation from the image describer.
        let caption: String?
        /// Whether retrieval surfaced this photo in its top-K.
        let retrieved: Bool
        let rank: Int?
        let score: Float?
    }

    struct Music: Codable {
        let title: String
        let artist: String?
        let persistentID: String
        let score: Float
        let highlightStartSeconds: Double?
        let highlightEndSeconds: Double?
    }

    let prompt: String
    let refinedImageQuery: String
    let caption: String
    let hashtags: [String]
    /// Photos handed to the pipeline as the "picked" set.
    let pickedPhotos: [String]
    /// Every picked photo with its caption and retrieval outcome.
    let photos: [Photo]
    let musicQuery: String
    let music: Music?
    let musicError: String?
    let retrievalError: String?
    /// Preference memory as read by this flow (pre-Post).
    let preferencesBeforePost: [CaseStudyPreferenceRow]
    /// ResultView's "What This Post Will Teach Your Agents" text.
    let pendingMemoryParagraph: String
}

struct CaseStudyPreferenceRow: Codable {
    let category: String
    let value: String
    let polarity: String
    let confidence: Double
    let evidenceCount: Int
    let explanation: String?
}

/// Preference memory right after "Post" was tapped.
struct CaseStudyPostMemorySnapshot: Codable {
    struct Signal: Codable {
        let category: String
        let value: String
        let polarity: String
        let count: Int
    }

    let preferences: [CaseStudyPreferenceRow]
    let todayInteractionCount: Int
    let todaySignals: [Signal]
}

enum CaseStudyResultExport {
    @MainActor
    static func allPreferences() -> [CaseStudyPreferenceRow] {
        PreferenceCategory.allCases.flatMap { category in
            MemoryManager.shared.getPreferences(for: category, minConfidence: 0).map {
                CaseStudyPreferenceRow(
                    category: $0.categoryRaw,
                    value: $0.value,
                    polarity: $0.polarityRaw,
                    confidence: $0.confidence,
                    evidenceCount: $0.evidenceCount,
                    explanation: $0.explanation
                )
            }
        }
    }

    @MainActor
    static func snapshot(model: AgentFlowModel, pendingMemoryParagraph: String) -> CaseStudyResultSnapshot {
        let ranked = Dictionary(
            uniqueKeysWithValues: model.retrievalResults.enumerated().map { ($1.id, ($0 + 1, $1.score)) }
        )
        // indexedCandidates is in the same order as selectedImages, which
        // is in selectedPhotoNames' order (ImageIndexer.index contract).
        let photos = model.indexedCandidates.enumerated().map { i, candidate in
            CaseStudyResultSnapshot.Photo(
                file: i < model.selectedPhotoNames.count ? model.selectedPhotoNames[i] : "unknown-\(i)",
                caption: candidate.caption,
                retrieved: ranked[candidate.id] != nil,
                rank: ranked[candidate.id]?.0,
                score: ranked[candidate.id]?.1
            )
        }
        let music = model.recommendedTrack.map {
            CaseStudyResultSnapshot.Music(
                title: $0.track.title,
                artist: $0.track.artist,
                persistentID: String($0.track.persistentID),
                score: $0.score,
                highlightStartSeconds: model.highlightRange?.lowerBound,
                highlightEndSeconds: model.highlightRange?.upperBound
            )
        }
        return CaseStudyResultSnapshot(
            prompt: model.prompt,
            refinedImageQuery: model.refinedQuery,
            caption: model.generatedCaption,
            hashtags: model.hashtags,
            pickedPhotos: model.selectedPhotoNames,
            photos: photos,
            musicQuery: model.musicQuery,
            music: music,
            musicError: model.musicError,
            retrievalError: model.retrievalError,
            preferencesBeforePost: allPreferences(),
            pendingMemoryParagraph: pendingMemoryParagraph
        )
    }

    @MainActor
    static func postMemorySnapshot() -> CaseStudyPostMemorySnapshot {
        let today = MemoryManager.shared.todaysSnapshot()
        return CaseStudyPostMemorySnapshot(
            preferences: allPreferences(),
            todayInteractionCount: today.interactionCount,
            todaySignals: today.signals.map {
                .init(category: $0.category.rawValue, value: $0.value, polarity: $0.polarity.rawValue, count: $0.count)
            }
        )
    }

    static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
