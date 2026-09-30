//
//  CaseStudyFixtures.swift
//  app-v1
//
//  Debug-only bypass for the OS27 case study measurement experiment: swaps
//  the interactive photo picker and the on-device Music library scan for a
//  fixed, bundled set of fixture photos/tracks, so this app and
//  app-v1-os27 run the pipeline against byte-identical input on a real
//  device, with no dependency on the test device's actual Photos/Music
//  library state.
//
//  The fixture files themselves live outside this repo, at
//  case-study/fixtures/{photos,music}, and are reached via the
//  `CaseStudyFixtures` symlink alongside this file (pointing at
//  ../../../case-study/fixtures) so both app-v1 and app-v1-os27 bundle the
//  exact same files without duplicating them. Nothing here changes the
//  normal (picker / library-scan) code paths — this is only consulted when
//  explicitly enabled.
//

import Foundation
import UIKit

enum CaseStudyFixtures {
#if DEBUG
    /// Pass `-UseCaseStudyFixtures` as a launch argument (Scheme editor, or
    /// XCUIApplication().launchArguments in a UI test) to enable.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UseCaseStudyFixtures")
    }
#else
    static var isEnabled: Bool { false }
#endif

    // Matched case-insensitively below — real device exports (e.g. Photos'
    // .JPG) are commonly uppercase.
    private static let imageExtensions = ["jpg", "jpeg", "png", "heic"]
    private static let audioExtensions = ["mp3", "m4a", "wav", "aac"]

    /// All bundled fixture photos, in a stable (filename) order.
    static func loadPhotos() -> [UIImage] {
        urls(inSubdirectory: "photos", extensions: imageExtensions)
            .compactMap { UIImage(contentsOfFile: $0.path) }
    }

    /// All bundled fixture audio files, in a stable (filename) order.
    static func musicFixtureURLs() -> [URL] {
        urls(inSubdirectory: "music", extensions: audioExtensions)
    }

    /// A stable synthetic `MPMediaItem.persistentID` stand-in, derived from
    /// the filename so it stays identical across runs and across both
    /// apps — both bundle the same files from the same shared fixtures
    /// folder, so the same filename always yields the same ID.
    static func persistentID(for url: URL) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037 // FNV-1a offset basis
        for byte in url.lastPathComponent.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211 // FNV-1a prime
        }
        return hash
    }

    /// Resolves a fixture's synthetic persistent ID back to its bundled
    /// file URL. The fixture-mode counterpart to `MediaLibraryLookup`,
    /// which only knows how to query the real on-device Music library —
    /// fixture tracks have no entry there, so highlight detection would
    /// otherwise silently find nothing for them.
    static func assetURL(forPersistentID persistentID: UInt64) -> URL? {
        musicFixtureURLs().first { self.persistentID(for: $0) == persistentID }
    }

    /// Looks for `CaseStudyFixtures/<subdirectory>/*.<ext>` in the app
    /// bundle first (the expected layout, preserved through the symlinked
    /// folder reference), falling back to a flattened `<subdirectory>/*`
    /// in case the build system doesn't preserve the nesting. Sorted by
    /// filename so ordering is stable across runs.
    private static func urls(inSubdirectory subdirectory: String, extensions: [String]) -> [URL] {
        let nestedSubdir = "CaseStudyFixtures/\(subdirectory)"
        let candidateExtensions = extensions + extensions.map { $0.uppercased() }
        var found: [URL] = []
        for ext in candidateExtensions {
            found += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nestedSubdir) ?? []
        }
        if found.isEmpty {
            for ext in candidateExtensions {
                found += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: subdirectory) ?? []
            }
        }
        // De-duplicate in case the filesystem's resource lookup treats
        // extensions case-insensitively and returns the same file twice.
        var seen = Set<String>()
        return found
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
