//
//  MemorySectionCard.swift
//  app-v1
//
//  A labeled card showing one MemoryNarrationAgent paragraph. Shared by
//  PromptInputView's "what your agents have learned" / "today" cards —
//  matches ResultView's sectionCard styling so memory content reads
//  consistently across screens.
//

import SwiftUI

struct MemorySectionCard: View {
    let title: String
    let systemImage: String
    let isLoading: Bool
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if isLoading && text.isEmpty {
                ProgressView()
            } else {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    VStack(spacing: 16) {
        MemorySectionCard(
            title: "What your agents have learned",
            systemImage: "brain",
            isLoading: false,
            text: "You tend to go for outdoor, landscape-heavy shots and skip selfies. Your music picks lean acoustic and upbeat."
        )
        MemorySectionCard(title: "Today", systemImage: "calendar", isLoading: true, text: "")
    }
    .padding(20)
}
