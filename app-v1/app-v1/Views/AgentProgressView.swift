//
//  AgentProgressView.swift
//  app-v1
//
//  Screen 3: runs the real on-device pipeline —
//  index selected photos (Florence caption + CLIP embed) -> turn Florence's
//  observations into a social-media caption (Caption Agent) -> refine the
//  query -> retrieve top-K matches — then hands off to ResultView.
//

import SwiftUI

private struct AgentStep: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
}

struct AgentProgressView: View {
    let model: AgentFlowModel
    @Binding var path: [FlowStep]

    private let steps: [AgentStep] = [
        AgentStep(title: "Indexing your photos", systemImage: "photo.badge.checkmark"),
        AgentStep(title: "Finding hashtags", systemImage: "number"),
        AgentStep(title: "Understanding your search", systemImage: "text.quote"),
        AgentStep(title: "Matching photos", systemImage: "photo.stack")
    ]

    @State private var completedCount = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.4)

            VStack(spacing: 4) {
                Text("Your agents are working")
                    .font(.title2.bold())
                Text("This will only take a moment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 14) {
                        Image(systemName: index < completedCount ? "checkmark.circle.fill" : step.systemImage)
                            .font(.title3)
                            .foregroundStyle(index < completedCount ? Color.green : Color.secondary)
                            .frame(width: 26)

                        Text(step.title)
                            .font(.body)
                            .foregroundStyle(index < completedCount ? .primary : .secondary)

                        Spacer()

                        if index == completedCount {
                            ProgressView()
                        }
                    }
                }
            }
            .padding(20)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding(20)
        .navigationTitle("Working")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task {
            await runPipeline()
        }
    }

    private func runPipeline() async {
        do {
            let indexed = try await ImageIndexer().index(model.selectedImages) { _ in }

            // Florence only supplies visual observations here; the Caption
            // Agent (on-device Foundation Model) turns them into the actual
            // social-media caption shown to the user.
            let observations = indexed
                .compactMap(\.caption)
                .joined(separator: " ")
            model.generatedCaption = await CaptionAgent().run(observations: observations)
            completedCount = 1

            let hashtagContext = HashtagContext(
                prompt: model.prompt,
                observations: observations,
                caption: model.generatedCaption
            )
            model.hashtags = await HashtagAgent().run(for: hashtagContext).hashtags
            completedCount = 2

            // Scoped to this flow's photos, not the whole persistent index
            // (which accumulates across sessions) — otherwise matches would
            // include photos from previous posts.
            let result = try await RetrievalAgent().run(query: model.prompt, topK: 20, candidates: indexed)
            model.refinedQuery = result.refinedQuery
            completedCount = 3

            model.retrievalResults = result.images
            completedCount = 4
        } catch {
            model.retrievalError = String(describing: error)
        }

        try? await Task.sleep(for: .seconds(0.3))
        path.append(.result)
    }
}

#Preview {
    NavigationStack {
        AgentProgressView(model: AgentFlowModel(), path: .constant([]))
    }
}
