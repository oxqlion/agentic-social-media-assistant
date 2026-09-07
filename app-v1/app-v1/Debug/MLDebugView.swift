//
//  MLDebugView.swift
//  app-v1
//
//  Development-only screen for exercising MLDebugHarness on-device.
//  Reached via a #if DEBUG toolbar button from PromptInputView.
//

#if DEBUG
import PhotosUI
import SwiftUI

struct MLDebugView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var queryText: String = "a photo of a dog on a beach"
    @State private var log: String = ""
    @State private var isBusy = false

    var body: some View {
        Form {
            Section("Test image") {
                PhotosPicker("Choose image", selection: $pickerItem, matching: .images)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 160)
                }
            }

            Section("Query") {
                TextField("Query text", text: $queryText)
            }

            Section("Run") {
                actionButton("1. Florence caption") { try await runFlorence() }
                actionButton("2. CLIP image encode") { try await runImageEncode() }
                actionButton("3. CLIP text encode") { try await runTextEncode() }
                actionButton("4. cosine(image, text)") { try await runSimilarity() }
                actionButton("5. Retrieve top-5") { try await runRetrieval() }
            }

            Section("Log") {
                Text(log.isEmpty ? "No runs yet." : log)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("ML Debug")
        .disabled(isBusy)
        .onChange(of: pickerItem) { _, newValue in
            Task {
                guard let newValue, let data = try? await newValue.loadTransferable(type: Data.self) else { return }
                image = UIImage(data: data)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, action: @escaping () async throws -> Void) -> some View {
        Button(title) {
            Task {
                isBusy = true
                defer { isBusy = false }
                do {
                    try await action()
                } catch {
                    append("ERROR: \(error)")
                }
            }
        }
    }

    private func append(_ line: String) {
        log = "\(line)\n\n\(log)"
    }

    private func requireImage() throws -> UIImage {
        guard let image else { throw MLDebugViewError.noImageSelected }
        return image
    }

    private func runFlorence() async throws {
        let result = try await MLDebugHarness.runFlorenceCaption(on: requireImage())
        append("Florence (\(String(format: "%.0f", result.milliseconds))ms): \(result.value)")
    }

    private func runImageEncode() async throws {
        let result = try await MLDebugHarness.runCLIPImageEncode(on: requireImage())
        append("CLIP image embed (\(String(format: "%.0f", result.milliseconds))ms): dim=\(result.value.count)")
    }

    private func runTextEncode() async throws {
        let result = try await MLDebugHarness.runCLIPTextEncode(queryText)
        append("CLIP text embed (\(String(format: "%.0f", result.milliseconds))ms): dim=\(result.value.count)")
    }

    private func runSimilarity() async throws {
        let result = try await MLDebugHarness.runImageTextSimilarity(image: requireImage(), text: queryText)
        append("cosine(image, text) (\(String(format: "%.0f", result.milliseconds))ms): \(result.value)")
    }

    private func runRetrieval() async throws {
        let result = try await MLDebugHarness.runRetrieval(query: queryText, topK: 5)
        let summary = result.value.map { "\($0.score)" }.joined(separator: ", ")
        append("Retrieval (\(String(format: "%.0f", result.milliseconds))ms): \(result.value.count) results [\(summary)]")
    }
}

private enum MLDebugViewError: Error {
    case noImageSelected
}

#Preview {
    NavigationStack {
        MLDebugView()
    }
}
#endif
