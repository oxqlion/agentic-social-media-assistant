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

    @State private var preferenceParagraph: String = ""
    @State private var todayParagraph: String = ""
    @State private var isLoadingMemory = false

    private var canContinue: Bool {
        !model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
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

                MemorySectionCard(
                    title: "What Your Agents Have Learned",
                    systemImage: "brain",
                    isLoading: isLoadingMemory,
                    text: preferenceParagraph
                )

                MemorySectionCard(
                    title: "Today",
                    systemImage: "calendar",
                    isLoading: isLoadingMemory,
                    text: todayParagraph
                )

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
        }
        .navigationTitle("New Post")
        .navigationBarTitleDisplayMode(.inline)
#if DEBUG
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("ML Debug") {
                    MLDebugView()
                }
            }
        }
#endif
        .task { await refreshMemory() }
        .onChange(of: path) { _, newPath in
            guard newPath.isEmpty else { return }
            Task { await refreshMemory() }
        }
    }

    /// Reloads both memory cards from MemoryManager — called on first
    /// appearance and whenever the flow resets back to this screen (e.g.
    /// "Start Over" on ResultView), since a post created in between may
    /// have changed what's in memory.
    private func refreshMemory() async {
        isLoadingMemory = true

        let manager = MemoryManager.shared
        let preferences = PreferenceCategory.allCases.flatMap { manager.getPreferences(for: $0) }
        let today = manager.todaysSnapshot()

        let narrator = MemoryNarrationAgent()
        async let preferenceText = narrator.summarizePreferences(preferences)
        async let todayText = narrator.summarizeToday(today)
        preferenceParagraph = await preferenceText
        todayParagraph = await todayText

        isLoadingMemory = false
    }
}

#Preview {
    NavigationStack {
        PromptInputView(model: AgentFlowModel(), path: .constant([]))
    }
}
