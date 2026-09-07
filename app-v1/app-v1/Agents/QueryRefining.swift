//
//  QueryRefining.swift
//  app-v1
//
//  The seam between "however we turn a user's raw prompt into a good CLIP
//  query" and the rest of the pipeline. Swapping the on-device language
//  model for something else later means implementing this protocol, not
//  touching RetrievalAgent or ImageRetriever.
//

protocol QueryRefining: Sendable {
    /// Refines a raw user query into text better suited to a CLIP search
    /// (e.g. more descriptive, closer to "a photo of ..." phrasing).
    /// Never throws: a refiner that can't help returns the input unchanged.
    func refine(_ query: String) async -> String
}

/// Refiner of last resort: passes the query through unchanged. Used when no
/// on-device language model is available.
struct PassthroughQueryRefiner: QueryRefining {
    func refine(_ query: String) async -> String { query }
}
