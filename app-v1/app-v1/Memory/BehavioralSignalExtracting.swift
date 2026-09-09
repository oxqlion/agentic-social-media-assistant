//
//  BehavioralSignalExtracting.swift
//  app-v1
//
//  Turns the raw outcome of a post-creation flow (which captions were
//  selected vs. rejected, which music query was accepted vs. rejected)
//  into BehavioralSignal tags. Pure keyword heuristics over text the
//  pipeline already produces (Florence captions, the music mood query) —
//  no new ML model, no new dependency.
//

import Foundation

enum BehavioralSignalExtractor {
    /// (keywords to match in a lowercased caption, the tag they map to).
    /// First match wins per caption per polarity bucket — a caption only
    /// contributes each tag once even if several of its keywords match.
    private static let imageKeywordTags: [(keywords: [String], value: String)] = [
        (["selfie", "self-portrait", "self portrait"], "selfie"),
        (["landscape", "scenery", "horizon", "mountain range", "skyline"], "landscape"),
        (["portrait", "close-up", "close up"], "portrait"),
        (["group photo", "group of people", "crowd"], "group_photo"),
        (["food", "meal", "dish", "plate of"], "food"),
        (["dog", "cat", "pet"], "pet"),
        (["night", "evening", "sunset", "sunrise"], "low_light"),
        (["outdoor", "outdoors", "nature", "beach", "park"], "outdoor"),
        (["indoor", "indoors", "room", "interior"], "indoor")
    ]

    /// Mood/genre words the music-query generator tends to produce
    /// (see FoundationModelMusicQueryGenerator) — tagged directly as the
    /// preference value rather than bucketed, since they're already
    /// short, specific descriptors.
    private static let musicMoodKeywords: [String] = [
        "acoustic", "upbeat", "calm", "energetic", "piano", "electronic",
        "chill", "instrumental", "slow", "fast", "ambient", "orchestral",
        "mellow", "dreamy", "nostalgic", "cinematic"
    ]

    static func imageSignals(selectedCaptions: [String], rejectedCaptions: [String]) -> [BehavioralSignal] {
        tagSignals(from: selectedCaptions, category: .image, polarity: .prefer)
            + tagSignals(from: rejectedCaptions, category: .image, polarity: .avoid)
    }

    static func musicSignals(acceptedQuery: String?, rejectedQueries: [String]) -> [BehavioralSignal] {
        var signals: [BehavioralSignal] = []
        if let acceptedQuery {
            signals += moodSignals(from: acceptedQuery, polarity: .prefer)
        }
        for query in rejectedQueries {
            signals += moodSignals(from: query, polarity: .avoid)
        }
        return signals
    }

    /// The image-theme tags (e.g. "landscape", "selfie") matched in one
    /// caption — exposed so ranking logic (see ImagePreferenceRanker) can
    /// recognize the same themes memory learns from, instead of keeping a
    /// second, driftable keyword table.
    static func imageTags(in caption: String) -> Set<String> {
        let lower = caption.lowercased()
        return imageKeywordTags.reduce(into: Set<String>()) { tags, tag in
            if tag.keywords.contains(where: { lower.contains($0) }) {
                tags.insert(tag.value)
            }
        }
    }

    private static func tagSignals(
        from captions: [String],
        category: PreferenceCategory,
        polarity: PreferencePolarity
    ) -> [BehavioralSignal] {
        var seenValues = Set<String>()
        var out: [BehavioralSignal] = []
        for caption in captions {
            for value in imageTags(in: caption) where !seenValues.contains(value) {
                out.append(BehavioralSignal(category: category, value: value, polarity: polarity))
                seenValues.insert(value)
            }
        }
        return out
    }

    private static func moodSignals(from query: String, polarity: PreferencePolarity) -> [BehavioralSignal] {
        guard !query.isEmpty else { return [] }
        let lower = query.lowercased()
        return musicMoodKeywords
            .filter { lower.contains($0) }
            .map { BehavioralSignal(category: .music, value: $0, polarity: polarity) }
    }
}
