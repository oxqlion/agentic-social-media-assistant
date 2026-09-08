//
//  CaptionAgent.swift
//  app-v1
//
//  Orchestration only: takes Florence's visual observations and turns them
//  into an engaging social-media caption. Florence stays purely a visual
//  understanding step — it never produces the final caption text.
//
//      Florence observations -> CaptionGenerating -> social-media caption
//

import Foundation

struct CaptionAgent {
    let generator: CaptionGenerating

    init(generator: CaptionGenerating = FoundationModelCaptionGenerator()) {
        self.generator = generator
    }

    /// Turns `observations` — Florence's raw visual description(s) of the
    /// selected photos — into a single engaging social-media caption.
    func run(observations: String) async -> String {
        guard !observations.isEmpty else { return observations }
        return await generator.generate(from: observations)
    }
}
