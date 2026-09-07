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
    }
}

#Preview {
    ContentView()
}
