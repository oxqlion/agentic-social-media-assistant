//
//  PromptInputView.swift
//  app-v1
//
//  Screen 1: the user describes what they want to post about.
//

import SwiftUI

struct PromptInputView: View {
    @Bindable var model: AgentFlowModel
    @Binding var path: [FlowStep]

    private var canContinue: Bool {
        !model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's the post about?")
                    .font(.largeTitle.bold())
                Text("Describe the moment and your AI agents will pick the best photos, write a caption, and find matching music.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))

                if model.prompt.isEmpty {
                    Text("e.g. A cozy coffee shop morning with my new book")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $model.prompt)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .frame(height: 160)

            Spacer()

            Button {
                path.append(.imageSelector)
            } label: {
                Text("Choose Photos")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canContinue ? Color.accentColor : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canContinue)
        }
        .padding(20)
        .navigationTitle("New Post")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PromptInputView(model: AgentFlowModel(), path: .constant([]))
    }
}
