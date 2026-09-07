//
//  ResultView.swift
//  app-v1
//
//  Screen 4: shows what the agents produced. All content here is a
//  placeholder — no real generation happens yet.
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

                sectionCard(title: "Caption", systemImage: "text.quote") {
                    Text("Placeholder caption text goes here. The real AI-generated caption will appear in this spot.")
                        .font(.body)
                        .foregroundStyle(.primary)
                }

                sectionCard(title: "Hashtags", systemImage: "number") {
                    Text("#placeholder #hashtag #comingsoon #agenticai")
                        .font(.body)
                        .foregroundStyle(.blue)
                }

                sectionCard(title: "Recommended Music", systemImage: "music.note") {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 48, height: 48)
                            .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Placeholder Song Title")
                                .font(.body.weight(.semibold))
                            Text("Placeholder Artist Name")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }

                sectionCard(title: "Track Segment", systemImage: "waveform") {
                    Text("0:45 – 1:15 (placeholder)")
                        .font(.body)
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

#Preview {
    NavigationStack {
        ResultView(model: AgentFlowModel(), path: .constant([]))
    }
}
