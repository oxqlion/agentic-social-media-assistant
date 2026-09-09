//
//  NewPostIntent.swift
//  app-v1
//
//  Siri/Spotlight entry point for the post-creation flow. Prompt-prefill
//  only: this intent hands the spoken/typed description straight to
//  ContentView via PendingPromptRouter and opens the app at the photo
//  picker — it does NOT run the on-device pipeline itself (see
//  Views/AgentProgressView.swift for why: multi-step Core ML + Foundation
//  Model inference is far too slow for an inline Siri response) and it does
//  NOT search the photo library on the user's behalf (see
//  Views/ImageSelectorView.swift — candidate photos are still a manual,
//  bounded PhotosPicker selection). The user still has to pick photos and
//  confirm before anything runs.
//

import AppIntents

struct NewPostIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a New Post"
    static let description = IntentDescription(
        "Starts a new post in app-v1 with your description already filled in, ready to pick photos."
    )

    /// Launch the app UI rather than trying to run the pipeline headlessly —
    /// there's no result to hand back to Siri until the user picks photos.
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Description", requestValueDialog: "What's the post about?")
    var prompt: String

    static var parameterSummary: some ParameterSummary {
        Summary("Start a new post about \(\.$prompt)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingPromptRouter.shared.pendingPrompt = prompt
        return .result()
    }
}
