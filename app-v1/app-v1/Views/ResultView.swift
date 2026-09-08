//
//  ResultView.swift
//  app-v1
//
//  Screen 4: shows what the agents produced — matching photos, caption,
//  hashtags, and recommended music are all real. Only the "Post" button
//  is a UI placeholder (no real posting action exists).
//

import SwiftUI

struct ResultView: View {
    @Bindable var model: AgentFlowModel
    @Binding var path: [FlowStep]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to post")
                        .font(.largeTitle.bold())
                    Text("Here's what your agents put together.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                sectionCard(title: "Selected Photos", systemImage: "photo.stack") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(model.selectedImages.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 110, height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .clipped()
                            }
                        }
                    }
                }

                if !model.retrievalResults.isEmpty {
                    sectionCard(title: "Matching Photos", systemImage: "sparkle.magnifyingglass") {
                        VStack(alignment: .leading, spacing: 8) {
                            if !model.refinedQuery.isEmpty {
                                Text("Searched for: \"\(model.refinedQuery)\"")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach(model.retrievalResults) { scored in
                                        VStack(alignment: .leading, spacing: 4) {
                                            RetrievalThumbnail(scored: scored)
                                                .frame(width: 110, height: 110)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                                .clipped()
                                            Text(String(format: "%.2f", scored.score))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            if let caption = scored.image.caption {
                                                Text(caption)
                                                    .font(.caption2)
                                                    .lineLimit(2)
                                                    .frame(width: 110, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if let retrievalError = model.retrievalError {
                    sectionCard(title: "Matching Photos", systemImage: "exclamationmark.triangle") {
                        Text(retrievalError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                sectionCard(title: "Caption", systemImage: "text.quote") {
                    if model.generatedCaption.isEmpty {
                        Text("No caption was generated for these photos.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.generatedCaption)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }

                sectionCard(title: "Hashtags", systemImage: "number") {
                    if model.hashtags.isEmpty {
                        Text("No hashtags were generated for these photos.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.hashtags.joined(separator: " "))
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                }

                sectionCard(title: "Recommended Music", systemImage: "music.note") {
                    VStack(alignment: .leading, spacing: 8) {
                        if !model.musicQuery.isEmpty {
                            Text("Searched for: \"\(model.musicQuery)\"")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let recommended = model.recommendedTrack {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.tertiarySystemFill))
                                    .frame(width: 48, height: 48)
                                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recommended.track.title)
                                        .font(.body.weight(.semibold))
                                    Text(recommended.track.artist ?? "Unknown Artist")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(String(format: "%.2f", recommended.score))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        } else if let musicError = model.musicError {
                            Text(musicError)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No matching music found on this device.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let recommended = model.recommendedTrack {
                    sectionCard(title: "Analyzed Segment", systemImage: "waveform") {
                        Text(
                            "\(formatTime(recommended.track.analyzedRange.lowerBound))"
                            + " – \(formatTime(recommended.track.analyzedRange.upperBound))"
                        )
                        .font(.body)
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        // No real posting action yet — UI placeholder only.
                    } label: {
                        Text("Post")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        model.reset()
                        path = []
                    } label: {
                        Text("Start Over")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RetrievalThumbnail: View {
    let scored: ScoredImage
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(.tertiarySystemFill))
            }
        }
        .task {
            let url = ImageEmbeddingStore.shared.thumbnailURL(for: scored.image)
            if let data = try? Data(contentsOf: url) {
                image = UIImage(data: data)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ResultView(model: AgentFlowModel(), path: .constant([]))
    }
}
