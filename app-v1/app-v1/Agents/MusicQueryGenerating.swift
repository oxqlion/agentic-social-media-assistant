//
//  MusicQueryGenerating.swift
//  app-v1
//
//  The seam between "however we turn the photos' visual context into a
//  good CLAP text query" and the rest of the pipeline — same shape as
//  QueryRefining. Swapping the on-device language model for something else
//  later means implementing this protocol, not touching MusicRecommenderAgent
//  or MusicRetriever.
//

protocol MusicQueryGenerating: Sendable {
    /// Turns visual `observations` (Florence) and the generated social
    /// `caption` into a short, CLAP-friendly music-mood phrase (e.g. "a
    /// warm, nostalgic acoustic tune"). Never throws: a generator that
    /// can't help falls back to the raw context text.
    func generateQuery(observations: String, caption: String) async -> String
}
