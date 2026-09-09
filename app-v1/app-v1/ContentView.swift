//
//  ContentView.swift
//  app-v1
//
//  Created by Rafi Abhista on 07/09/26.
//

import SwiftUI

struct ContentView: View {
    @State private var model = AgentFlowModel()
    @State private var path: [FlowStep] = []
    private var router = PendingPromptRouter.shared

    var body: some View {
        NavigationStack(path: $path) {
            PromptInputView(model: model, path: $path)
                .navigationDestination(for: FlowStep.self) { step in
                    switch step {
                    case .imageSelector:
                        ImageSelectorView(model: model, path: $path)
                    case .progress:
                        AgentProgressView(model: model, path: $path)
                    case .result:
                        ResultView(model: model, path: $path)
                    }
                }
        }
        .task { consumePendingPrompt() }
        .onChange(of: router.pendingPrompt) { _, _ in consumePendingPrompt() }
    }

    /// Called on first appearance (cold launch: NewPostIntent already wrote
    /// the prompt before this view existed) and again on every change
    /// (warm launch: app was already open when the intent ran). Resets the
    /// in-progress flow, if any, so a Siri-triggered post always starts
    /// clean rather than clobbering mid-flow state.
    private func consumePendingPrompt() {
        guard let prompt = router.pendingPrompt else { return }
        router.pendingPrompt = nil

        model.reset()
        model.prompt = prompt
        path = [.imageSelector]
    }
}

#Preview {
    ContentView()
}
