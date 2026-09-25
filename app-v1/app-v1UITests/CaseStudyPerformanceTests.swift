//
//  CaseStudyPerformanceTests.swift
//  app-v1UITests
//
//  OS27 case study: controlled, on-device performance benchmark. Drives
//  the real end-to-end flow — prompt -> photos -> agent pipeline -> result
//  — through the app's CaseStudyFixtures bypass (see
//  app-v1/CaseStudy/CaseStudyFixtures.swift), so every trial runs against
//  identical bundled photos/music/prompts instead of the device's live
//  Photos/Music library or hand-typed text. See
//  notes/comparison-experiment-plan.md for the full experiment design.
//
//  Two variants:
//   - testColdPipelinePerformance: relaunches the app fresh every trial —
//     includes app launch + first-call model loading.
//   - testWarmPipelinePerformance: launches once, then loops the flow via
//     "Start Over" — steady-state, already-loaded performance.
//
//  Neither taps "Post" — the flow is measured up to ResultView only, so
//  MemoryManager is never written to during a run (nothing to reset
//  between iterations). It IS reset once at launch in test mode — see
//  app_v1App.swift — so reads during the pipeline (preference-nudged
//  ranking/captions) start from an identical, empty state every trial.
//
//  Per-stage timing comes from the app's existing MLPerfLog os_signpost
//  instrumentation (ML/MLPerfLog.swift) via XCTOSSignpostMetric. The names
//  below are app-v1's current implementation's stage names; once
//  app-v1-os27 replaces Florence / the custom highlight detector with
//  Foundation Models Vision / Music Understanding, add its new stage
//  names to this same list so one test measures both sides comparably.
//

import XCTest

final class CaseStudyPerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// MLPerfLog stage names this benchmark reads — see ML/MLPerfLog.swift
    /// call sites across the app for the full set instrumented today.
    private static let signpostStages: [String] = [
        "model.load",
        "florence.encoder.inference",
        "florence.decoder.step",
        "clip.image.inference",
        "retrieval.textEmbed",
        "retrieval.rank",
        "agent.query.refine",
        "agent.caption.generate",
        "agent.hashtag.extract",
        "clap.audio.inference",
        "agent.music.generate",
        "music.retrieval.textEmbed",
        "music.retrieval.rank",
        "agent.music.highlight",
        "highlight.decode",
        "highlight.chroma",
        "highlight.novelty",
    ]

    private func performanceMetrics() -> [XCTMetric] {
        let signposts: [XCTMetric] = Self.signpostStages.map {
            XCTOSSignpostMetric(subsystem: "com.c3.app-v1", category: "ml", name: $0)
        }
        return [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()] + signposts
    }

    private func launchIntoFixtureMode() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UseCaseStudyFixtures"]
        app.launch()
        return app
    }

    /// Drives one full flow: PromptInputView -> ImageSelectorView ->
    /// AgentProgressView -> ResultView. Assumes `app` is currently showing
    /// PromptInputView (true on a fresh launch, and again after tapping
    /// "Start Over" on ResultView).
    private func runOnePipelineFlow(_ app: XCUIApplication, prompt: String) {
        let promptField = app.textViews["promptTextEditor"]
        XCTAssertTrue(promptField.waitForExistence(timeout: 10), "PromptInputView did not appear")
        promptField.tap()
        promptField.typeText(prompt)

        let choosePhotosButton = app.buttons["choosePhotosButton"]
        wait(for: choosePhotosButton, isEnabled: true, timeout: 5)
        choosePhotosButton.tap()

        // Fixture mode pre-fills the photo grid asynchronously (see
        // ImageSelectorView's .task); Continue stays disabled until that
        // finishes populating model.selectedImages.
        let continueButton = app.buttons["continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10), "ImageSelectorView did not appear")
        wait(for: continueButton, isEnabled: true, timeout: 10)
        continueButton.tap()

        let resultView = app.scrollViews["resultView"]
        XCTAssertTrue(resultView.waitForExistence(timeout: 120), "Pipeline did not reach ResultView in time")
    }

    private func wait(for element: XCUIElement, isEnabled: Bool, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "isEnabled == %@", NSNumber(value: isEnabled))
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    @MainActor
    func testColdPipelinePerformance() throws {
        let prompts = UITestFixtures.loadPrompts()
        XCTAssertFalse(prompts.isEmpty, "No prompts found in case-study/fixtures/prompts.json")

        var promptIndex = 0
        measure(metrics: performanceMetrics()) {
            let app = launchIntoFixtureMode()
            runOnePipelineFlow(app, prompt: prompts[promptIndex % prompts.count])
            promptIndex += 1
            app.terminate()
        }
    }

    @MainActor
    func testWarmPipelinePerformance() throws {
        let prompts = UITestFixtures.loadPrompts()
        XCTAssertFalse(prompts.isEmpty, "No prompts found in case-study/fixtures/prompts.json")

        let app = launchIntoFixtureMode()
        defer { app.terminate() }

        var promptIndex = 0
        measure(metrics: performanceMetrics()) {
            runOnePipelineFlow(app, prompt: prompts[promptIndex % prompts.count])
            promptIndex += 1
            app.buttons["startOverButton"].tap()
        }
    }
}
