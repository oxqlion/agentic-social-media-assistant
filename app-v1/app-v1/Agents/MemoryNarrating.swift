//
//  MemoryNarrating.swift
//  app-v1
//
//  The seam between "however we turn plain memory facts into a readable
//  paragraph" and the rest of the pipeline. Swapping the on-device language
//  model for something else later means implementing this protocol, not
//  touching MemoryNarrationAgent or the views that display its output.
//

protocol MemoryNarrating: Sendable {
    /// Turns a plain-text list of memory facts (e.g. "prefers landscape
    /// (image); avoids selfie (image)") into a short, natural paragraph.
    /// Never throws: a generator that can't help returns the facts
    /// unchanged.
    func narrate(from facts: String) async -> String
}

/// Generator of last resort: passes the raw facts through unchanged. Used
/// when no on-device language model is available.
struct PassthroughMemoryNarrator: MemoryNarrating {
    func narrate(from facts: String) async -> String { facts }
}
