//
//  PreferenceInstructions.swift
//  app-v1
//
//  OS27 Dynamic Instructions: one reusable, composable instruction block for
//  "this user's learned preferences", shared by the caption, hashtag and
//  music-query agents instead of each gluing preference text into its prompt.
//  Contributes nothing when there are no facts, so agents never special-case
//  an empty preference list.
//

import FoundationModels

struct PreferenceInstructions: DynamicInstructions {
    /// Compact fact list, see UserPreferenceMemory.asPromptFacts.
    let facts: String
    /// Lead-in sentence describing what the facts are and how loosely to
    /// follow them, e.g. "This user's music taste from past posts (follow loosely):".
    let lead: String

    var body: some DynamicInstructions {
        if !facts.isEmpty {
            Instructions {
                "\(lead) \(facts)."
            }
        }
    }
}
