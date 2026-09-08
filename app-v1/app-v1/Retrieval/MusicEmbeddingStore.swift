//
//  MusicEmbeddingStore.swift
//  app-v1
//
//  Local, persistent cache of indexed songs (embedding + metadata), backed
//  by a JSON manifest in Application Support — same shape as
//  ImageEmbeddingStore, keyed by `MPMediaItem.persistentID` instead of a
//  freshly-minted UUID so MusicIndexer can tell which songs are already
//  cached without re-encoding them. An `actor` so concurrent writes stay
//  serialized without an explicit lock.
//

import Foundation

actor MusicEmbeddingStore {
    static let shared = MusicEmbeddingStore()

    private let directoryURL: URL
    private let manifestURL: URL
    private var tracksByID: [UInt64: IndexedTrack] = [:]
    private var loaded = false

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(rootDirectory: appSupport.appendingPathComponent("MusicIndex", isDirectory: true))
    }

    /// Exposed (rather than purely private) so tests can point the store at
    /// an isolated temporary directory instead of the shared instance.
    init(rootDirectory: URL) {
        directoryURL = rootDirectory
        manifestURL = rootDirectory.appendingPathComponent("manifest.json")
    }

    func allTracks() throws -> [IndexedTrack] {
        try ensureLoaded()
        return Array(tracksByID.values)
    }

    /// Every persistentID currently cached — MusicIndexer diffs the live
    /// library's IDs against this to find which songs are actually new.
    func cachedPersistentIDs() throws -> Set<UInt64> {
        try ensureLoaded()
        return Set(tracksByID.keys)
    }

    var count: Int {
        get throws {
            try ensureLoaded()
            return tracksByID.count
        }
    }

    /// Persists a newly-indexed track (or replaces an existing entry with
    /// the same persistentID).
    func add(_ track: IndexedTrack) throws {
        try ensureLoaded()
        tracksByID[track.persistentID] = track
        try persist()
    }

    /// Drops cached entries whose persistentID isn't in `keepIDs` — called
    /// with the live library's current ID set so songs removed from the
    /// device don't linger in the index forever.
    func pruneTracks(notIn keepIDs: Set<UInt64>) throws {
        try ensureLoaded()
        tracksByID = tracksByID.filter { keepIDs.contains($0.key) }
        try persist()
    }

    func removeAll() throws {
        try FileManager.default.removeItem(at: directoryURL)
        tracksByID = [:]
        loaded = true
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        loaded = true
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            tracksByID = [:]
            return
        }
        let data = try Data(contentsOf: manifestURL)
        let tracks = try JSONDecoder().decode([IndexedTrack].self, from: data)
        tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.persistentID, $0) })
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Array(tracksByID.values))
        try data.write(to: manifestURL, options: .atomic)
    }
}
