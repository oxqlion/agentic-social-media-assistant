//
//  AgentProgressView.swift
//  app-v1
//
//  Screen 3: a purely cosmetic "agents at work" screen. No real agent
//  logic runs here yet — steps advance on a timer for demo purposes.
//

import SwiftUI

private struct AgentStep: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
}

struct AgentProgressView: View {
    @Binding var path: [FlowStep]

    private let steps: [AgentStep] = [
        AgentStep(title: "Analyzing your photos", systemImage: "photo.badge.checkmark"),
        AgentStep(title: "Writing your caption", systemImage: "text.quote"),
        AgentStep(title: "Finding trending hashtags", systemImage: "number"),
        AgentStep(title: "Matching the perfect track", systemImage: "music.note")
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
            await runSimulatedProgress()
        }
    }

    private func runSimulatedProgress() async {
        for _ in steps {
            try? await Task.sleep(for: .seconds(0.9))
            completedCount += 1
        }
        try? await Task.sleep(for: .seconds(0.4))
        path.append(.result)
    }
}

#Preview {
    NavigationStack {
        AgentProgressView(path: .constant([]))
    }
}
