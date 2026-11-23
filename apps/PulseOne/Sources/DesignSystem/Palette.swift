import SwiftUI

/// Legacy names, kept until every screen uses `DKColor` (DesignKit). Values come from the DesignKit tokens,
/// so old and new screens already share one palette. New code: use `DKColor`.
enum Palette {
    static let obsidian      = DKColor.obsidian
    static let bioCyan       = DKColor.bioCyan
    static let neuralViolet  = DKColor.neuralViolet
    static let pulseCoral    = DKColor.pulseCoral
    static let iceWhite      = DKColor.iceWhite

    static let surface       = DKColor.background
    static let surfaceRaised = DKColor.surface
    static let hairline      = DKColor.hairline
    static let surfaceButton = DKColor.surfaceRaised
    static let ink           = DKColor.textPrimary
    static let inkMuted      = DKColor.textSecondary

    static let mesh: [Color] = DKColor.backgroundMesh
}
