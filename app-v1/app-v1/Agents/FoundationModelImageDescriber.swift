//
//  FoundationModelImageDescriber.swift
//  app-v1
//
//  OS27 replacement for FlorenceCaptioner: the on-device Foundation Model
//  looks at the photo directly (image attachment in the prompt) and returns
//  one plain visual description. Fully on-device. Returns nil when Apple
//  Intelligence is unavailable (or the model can't take images) — the photo
//  then simply has no caption, the same state a Florence failure produced.
//

import Foundation
import FoundationModels
import UIKit

struct FoundationModelImageDescriber: ImageDescribing {
    private static let instructions = """
    You describe photos for a photo-selection app. Reply with exactly one \
    plain sentence describing the visual content: objects, scenery, and \
    setting. Do not add opinions, mood, or style, and do not mention that \
    it is a photo.
    """

    func describe(_ image: UIImage) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            MLPerfLog.info("foundation model unavailable, no image description")
            return nil
        }
        guard model.capabilities.contains(.vision) else {
            MLPerfLog.info("foundation model has no vision capability, no image description")
            return nil
        }

        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await MLPerfLog.measure("agent.image.describe") {
                try await session.respond {
                    "Describe this photo."
                    Attachment(image)
                }
            }
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            MLPerfLog.info("image description failed: \(error)")
            return nil
        }
    }
}
