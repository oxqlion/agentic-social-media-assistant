//
//  ImageSelectorView.swift
//  app-v1
//
//  Screen 2: the user picks which photos should be considered for the post.
//

import SwiftUI
import PhotosUI

struct ImageSelectorView: View {
    @Bindable var model: AgentFlowModel
    @Binding var path: [FlowStep]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 16) {
            PhotosPicker(
                selection: $model.selectedPickerItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Select Photos", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if model.selectedImages.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No photos selected yet")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(model.selectedImages.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .clipped()
                        }
                    }
                }

                Text("\(model.selectedImages.count) photo\(model.selectedImages.count == 1 ? "" : "s") selected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                path.append(.progress)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(model.selectedImages.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(model.selectedImages.isEmpty)
        }
        .padding(20)
        .navigationTitle("Select Photos")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.selectedPickerItems) { _, newItems in
            loadImages(from: newItems)
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) {
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            await MainActor.run {
                model.selectedImages = images
            }
        }
    }
}

#Preview {
    NavigationStack {
        ImageSelectorView(model: AgentFlowModel(), path: .constant([]))
    }
}
