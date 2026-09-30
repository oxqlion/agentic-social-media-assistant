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
//  Timing covers the flow up to ResultView only (`stopMeasuring()` once it
//  appears). After that — outside the measured section — each trial reads
//  what the pipeline produced (caption, hashtags, photos, music, preference
//  memory; see CaseStudy/CaseStudyResultExport.swift in the app), taps
//  "Post", reads the resulting preference memory, and attaches it all to
//  the .xcresult as `case-study-output-<test>-trial-<n>.json`.
//  case-study/scripts/extract_outputs.py copies those into
//  case-study/results/<run>/.
//
//  Post writes MemoryManager, so in the warm test (one launch, many
//  trials) preference memory accumulates trial to trial, and later trials'
//  ranking/captions are nudged by earlier posts. The cold test relaunches
//  every trial, and MemoryManager is reset at launch in test mode (see
//  app_v1App.swift), so every cold trial starts from identical, empty
//  memory; the warm test starts empty and then accumulates.
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
        // Once-per-flow aggregates of the per-item stages (florence.*, clap.audio.*,
        // clip.image.*, agent.image.describe). Those fire a variable number of times
        // per flow, so XCTOSSignpostMetric silently dropped them; read the device log
        // for their per-call numbers.
        "index.captioning.total",
        "index.clipEmbedding.total",
        "index.clapEmbedding.total",
        "retrieval.textEmbed",
        "retrieval.rank",
        "agent.query.refine",
        "agent.caption.generate",
        "agent.hashtag.extract",
        "agent.music.generate",
        "music.retrieval.textEmbed",
        "music.retrieval.rank",
        "agent.music.highlight",
        "highlight.decode",
        "highlight.chroma",
        "highlight.novelty",
        // OS27 replacements (see OS27Models): Foundation Models Vision
        // describer and Music Understanding highlight detector.
        "highlight.musicunderstanding",
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
        // Core AI run: `TEST_RUNNER_OS27_USE_COREAI=1 xcodebuild test ...` (xcodebuild strips
        // the TEST_RUNNER_ prefix). Default is the Core ML path, as in the baseline.
        if ProcessInfo.processInfo.environment["OS27_USE_COREAI"] == "1" {
            app.launchArguments += ["-os27UseCoreAI", "YES"]
        }
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
        XCTAssertTrue(resultView.waitForExistence(timeout: 600), "Pipeline did not reach ResultView in time")
    }

    private func jsonObject(from element: XCUIElement) -> Any? {
        guard let text = element.value as? String, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Runs on ResultView, after `stopMeasuring()`: reads the pipeline's
    /// outputs from the app's hidden export elements, taps Post, reads the
    /// preference memory it produced, and attaches both as one JSON file.
    private func captureOutputs(_ app: XCUIApplication, test: String, trial: Int, prompt: String) {
        let resultElement = app.descendants(matching: .any)["caseStudyResultJSON"]
        XCTAssertTrue(resultElement.waitForExistence(timeout: 180), "caseStudyResultJSON did not appear on ResultView")
        let result = jsonObject(from: resultElement)
        XCTAssertNotNil(result, "caseStudyResultJSON was not valid JSON")

        app.buttons["postButton"].tap()
        let postMemoryElement = app.descendants(matching: .any)["caseStudyPostMemoryJSON"]
        XCTAssertTrue(postMemoryElement.waitForExistence(timeout: 30), "caseStudyPostMemoryJSON did not appear after Post")
        let postMemory = jsonObject(from: postMemoryElement)

        let output: [String: Any] = [
            "test": test,
            "trial": trial,
            "prompt": prompt,
            "result": result ?? NSNull(),
            "memoryAfterPost": postMemory ?? NSNull(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) else {
            XCTFail("Could not serialize case-study output")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "case-study-output-\(test)-trial-\(trial).json"
        attachment.lifetime = .keepAlways
        add(attachment)
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
            let prompt = prompts[promptIndex % prompts.count]
            runOnePipelineFlow(app, prompt: prompt)
            stopMeasuring()
            captureOutputs(app, test: "cold", trial: promptIndex, prompt: prompt)
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
            let prompt = prompts[promptIndex % prompts.count]
            runOnePipelineFlow(app, prompt: prompt)
            stopMeasuring()
            captureOutputs(app, test: "warm", trial: promptIndex, prompt: prompt)
            promptIndex += 1
            app.buttons["startOverButton"].tap()
        }
    }
}
