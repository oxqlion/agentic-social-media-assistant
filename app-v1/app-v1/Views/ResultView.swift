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

    @State private var player = HighlightPlayer()
    @State private var pendingMemoryParagraph: String = ""
    @State private var isLoadingPendingMemory = true
    /// Case study fixture mode only: JSON of the preference memory right
    /// after "Post" was tapped. See CaseStudy/CaseStudyResultExport.swift.
    @State private var caseStudyPostMemoryJSON: String?

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
                    sectionCard(title: "Highlight", systemImage: "waveform") {
                        if let highlightRange = model.highlightRange {
                            HStack {
                                Text("\(formatTime(highlightRange.lowerBound)) – \(formatTime(highlightRange.upperBound))")
                                    .font(.body)

                                Spacer()

                                Button {
                                    if let url = MediaLibraryLookup.assetURL(forPersistentID: recommended.track.persistentID) {
                                        player.toggle(url: url, range: highlightRange)
                                    }
                                } label: {
                                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 30))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        } else {
                            Text("Couldn't detect a highlight for this track.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                sectionCard(title: "What This Post Will Teach Your Agents", systemImage: "brain") {
                    if isLoadingPendingMemory && pendingMemoryParagraph.isEmpty {
                        ProgressView()
                    } else {
                        Text(pendingMemoryParagraph)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        recordPostToMemory()
                        if CaseStudyFixtures.isEnabled {
                            caseStudyPostMemoryJSON = CaseStudyResultExport.json(CaseStudyResultExport.postMemorySnapshot())
                        }
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
                    .accessibilityIdentifier("postButton")

                    Button {
                        player.stop()
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
                    .accessibilityIdentifier("startOverButton")
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .accessibilityIdentifier("resultView")
        .overlay(alignment: .topLeading) { caseStudyExportProbes }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onDisappear { player.stop() }
        .task { await loadPendingMemoryParagraph() }
    }

    /// This flow's outcome in MemoryManager's terms — which images the
    /// retrieval agent surfaced vs. which candidate photos got passed
    /// over, and whether a music recommendation was produced. Shared by
    /// the "what this post will teach your agents" preview and the actual
    /// recordPost call, so the preview never drifts from what actually
    /// gets written.
    private func pendingPostOutcome() -> (selected: [PostImageOutcome], rejected: [PostImageOutcome], music: PostMusicOutcome?) {
        let selectedIDs = Set(model.retrievalResults.map(\.id))
        let selectedImages = model.retrievalResults.map {
            PostImageOutcome(id: $0.image.id.uuidString, caption: $0.image.caption)
        }
        let rejectedImages = model.indexedCandidates
            .filter { !selectedIDs.contains($0.id) }
            .map { PostImageOutcome(id: $0.id.uuidString, caption: $0.caption) }

        let acceptedMusic = model.recommendedTrack.map {
            PostMusicOutcome(id: String($0.track.persistentID), query: model.musicQuery)
        }

        return (selectedImages, rejectedImages, acceptedMusic)
    }

    /// Feeds this flow's outcome to the persistent preference memory. See
    /// Memory/MemoryManager.swift.
    private func recordPostToMemory() {
        let outcome = pendingPostOutcome()
        MemoryManager.shared.recordPost(
            prompt: model.prompt,
            selectedImages: outcome.selected,
            rejectedImages: outcome.rejected,
            acceptedMusic: outcome.music
        )
    }

    /// Generates the "what this post will teach your agents" paragraph
    /// from the same BehavioralSignal extraction MemoryManager.recordPost
    /// uses internally — a preview only, nothing is written to memory
    /// until the Post button is actually tapped.
    private func loadPendingMemoryParagraph() async {
        isLoadingPendingMemory = true

        let outcome = pendingPostOutcome()
        var signals = BehavioralSignalExtractor.imageSignals(
            selectedCaptions: outcome.selected.compactMap(\.caption),
            rejectedCaptions: outcome.rejected.compactMap(\.caption)
        )
        signals += BehavioralSignalExtractor.musicSignals(
            acceptedQuery: outcome.music?.query,
            rejectedQueries: []
        )

        pendingMemoryParagraph = await MemoryNarrationAgent().summarizePendingPost(signals: signals)
        isLoadingPendingMemory = false
    }

    /// Case study fixture mode only: invisible 1pt accessibility elements
    /// whose values carry the flow's outputs as JSON, so the UI test (a
    /// separate process) can read and attach them. The result element only
    /// appears once the pending-memory paragraph has loaded, so it is
    /// complete when it exists. See CaseStudy/CaseStudyResultExport.swift.
    @ViewBuilder
    private var caseStudyExportProbes: some View {
        if CaseStudyFixtures.isEnabled {
            ZStack {
                if !isLoadingPendingMemory {
                    caseStudyProbe(
                        "caseStudyResultJSON",
                        json: CaseStudyResultExport.json(
                            CaseStudyResultExport.snapshot(model: model, pendingMemoryParagraph: pendingMemoryParagraph)
                        )
                    )
                }
                if let caseStudyPostMemoryJSON {
                    caseStudyProbe("caseStudyPostMemoryJSON", json: caseStudyPostMemoryJSON)
                }
            }
        }
    }

    private func caseStudyProbe(_ identifier: String, json: String) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier(identifier)
            .accessibilityValue(json)
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
