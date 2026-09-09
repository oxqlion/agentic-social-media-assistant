//
//  CaptionGenerating.swift
//  app-v1
//
//  The seam between "however we turn Florence's visual observations into an
//  engaging social-media caption" and the rest of the pipeline. Swapping the
//  on-device language model for something else later means implementing
//  this protocol, not touching CaptionAgent or ImageIndexer.
//

protocol CaptionGenerating: Sendable {
    /// Turns Florence's raw visual observations (e.g. "A tall building with
    /// a clock tower and blue sky.") into a natural, engaging social-media
    /// caption. `preferenceContext` is an optional plain-fact style hint
    /// (e.g. "likes landscape, avoids selfie", see
    /// UserPreferenceMemory.asPromptFacts) — implementations should treat
    /// it as a loose style nudge, never as license to describe something
    /// not actually in `observations`. Never throws: a generator that
    /// can't help returns the observations unchanged.
    func generate(from observations: String, preferenceContext: String) async -> String
}

/// Generator of last resort: passes Florence's observations through
/// unchanged. Used when no on-device language model is available.
struct PassthroughCaptionGenerator: CaptionGenerating {
    func generate(from observations: String, preferenceContext: String) async -> String { observations }
}
