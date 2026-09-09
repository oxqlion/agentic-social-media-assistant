//
//  MediaLibraryLookup.swift
//  app-v1
//
//  The only other place (besides MusicIndexer) that touches MediaPlayer:
//  resolving a cached IndexedTrack's persistentID back to a playable file
//  URL. IndexedTrack deliberately doesn't carry this itself (see its own
//  doc comment — it "knows nothing about Core ML or MediaPlayer"), so
//  anything needing the raw file, like TrackHighlightDetecting, looks it
//  up fresh here.
//

import Foundation
import MediaPlayer

enum MediaLibraryLookup {
    static func assetURL(forPersistentID persistentID: UInt64) -> URL? {
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(
            MPMediaPropertyPredicate(value: persistentID, forProperty: MPMediaItemPropertyPersistentID)
        )
        return query.items?.first?.assetURL
    }
}
