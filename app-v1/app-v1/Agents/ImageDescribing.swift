//
//  ImageDescribing.swift
//  app-v1
//
//  The seam between "however we turn one photo into a plain visual
//  description" and ImageIndexer. Florence and the OS27 Foundation Models
//  describer are interchangeable behind it. Per-photo on purpose: preference
//  ranking and learning read each photo's description separately, including
//  photos the user did not pick.
//

import UIKit

protocol ImageDescribing: Sendable {
    /// One plain-language description of a single photo (objects, scenery,
    /// setting). Never throws: an implementation that can't help returns nil,
    /// which the rest of the app already treats as "no caption".
    func describe(_ image: UIImage) async -> String?
}
