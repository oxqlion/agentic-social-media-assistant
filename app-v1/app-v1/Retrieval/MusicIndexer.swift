//
//  MusicIndexer.swift
//  app-v1
//
//  UIImage -> Florence -> CLIP's music-shaped counterpart: MPMediaItem ->
//  waveform -> CLAP audio embedding -> local index. Diffs the live library
//  against MusicEmbeddingStore's cache so only new songs are decoded and
//  encoded — most scans after the first are a no-op. Cloud-only Apple
//  Music tracks (no local file) are skipped; there's nothing to decode.
//

import Foundation
import MediaPlayer

enum MusicIndexerError: Error {
    case libraryAccessDenied
}

struct MusicIndexer {
    enum Stage: Sendable {
        case scanning
        case encoding(completed: Int, total: Int)
    }

    private let encoder: CLAPEncoder
    private let store: MusicEmbeddingStore

    init(encoder: CLAPEncoder = .shared, store: MusicEmbeddingStore = .shared) {
        self.encoder = encoder
        self.store = store
    }

    /// Scans the on-device Music library, encodes any locally-downloaded
    /// song not already cached, and prunes cache entries for songs no
    /// longer in the library. Returns the full (now up to date) index.
    @discardableResult
    func indexLibrary(onProgress: @Sendable (Stage) async -> Void = { _ in }) async throws -> [IndexedTrack] {
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            _ = await MPMediaLibrary.requestAuthorization()
        }
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            throw MusicIndexerError.libraryAccessDenied
        }

        await onProgress(.scanning)
        let items = (MPMediaQuery.songs().items ?? []).filter { $0.assetURL != nil }

        let currentIDs = Set(items.map(\.persistentID))
        try await store.pruneTracks(notIn: currentIDs)

        let cachedIDs = try await store.cachedPersistentIDs()
        let newItems = items.filter { !cachedIDs.contains($0.persistentID) }

        for (i, item) in newItems.enumerated() {
            try Task.checkCancellation()
            if let url = item.assetURL {
                do {
                    let window = try AudioWaveformLoader.loadWindow(from: url)
                    let embedding = try await encoder.encodeAudio(window.samples)
                    let track = IndexedTrack(
                        persistentID: item.persistentID,
                        embedding: embedding,
                        title: item.title ?? "Unknown Title",
                        artist: item.artist,
                        duration: item.playbackDuration,
                        analyzedRange: window.range
                    )
                    try await store.add(track)
                } catch {
                    MLPerfLog.info("music index failed for \(item.title ?? "?"): \(error)")
                }
            }
            await onProgress(.encoding(completed: i + 1, total: newItems.count))
        }
        await encoder.unload()

        return try await store.allTracks()
    }
}
