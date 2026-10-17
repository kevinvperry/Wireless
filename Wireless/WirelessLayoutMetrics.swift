import SwiftUI

/// Wireless counterparts of Autohop's AdaptiveEditorialMetrics and
/// AdaptiveListRowMetrics. Keep matching controls on the same width bands.
struct WirelessLayoutMetrics {
    enum Band { case narrow, standard, wide, expansive }

    let band: Band

    /// Matches Autohop's AdaptiveLayoutMetrics.settingsSectionSpacing.
    static let settingsSectionSpacing: CGFloat = 48

    init(width: CGFloat) {
        switch min(max(width, 0), 1_100) {
        case ..<340: band = .narrow
        case ..<500: band = .standard
        case ..<700: band = .wide
        default: band = .expansive
        }
    }

    var horizontalGutter: CGFloat { switch band { case .narrow: 12; case .standard: 16; case .wide: 20; case .expansive: 28 } }
    var contentScale: CGFloat { switch band { case .narrow: 0.92; case .standard: 1; case .wide: 1.15; case .expansive: 1.3 } }
    var usesWidePlayerLayout: Bool { band == .expansive }
    var playerMaximumWidth: CGFloat { 1_100 }
    var listMaximumWidth: CGFloat { 900 }
    var formMaximumWidth: CGFloat { 720 }
    var tileMinimumWidth: CGFloat { switch band { case .narrow: 138; case .standard: 145; case .wide: 180; case .expansive: 220 } }
    var tileMaximumWidth: CGFloat { switch band { case .narrow, .standard: 280; case .wide: 320; case .expansive: 360 } }
    var tileSpacing: CGFloat { switch band { case .narrow: 10; case .standard: 14; case .wide: 16; case .expansive: 18 } }
    var discoverHeading: CGFloat { switch band { case .narrow: 23; case .standard: 26; case .wide: 31; case .expansive: 36 } }
    var discoverSectionTitle: CGFloat { switch band { case .narrow, .standard: 20; case .wide: 24; case .expansive: 28 } }
    var discoverSectionSpacing: CGFloat { switch band { case .narrow: 14; case .standard: 18; case .wide: 22; case .expansive: 26 } }
    var discoverQuickIcon: CGFloat { switch band { case .narrow, .standard: 18; case .wide: 21; case .expansive: 24 } }
    var discoverQuickIconFrame: CGFloat { switch band { case .narrow: 38; case .standard: 42; case .wide: 48; case .expansive: 54 } }
    var discoverQuickTileHeight: CGFloat { switch band { case .narrow: 82; case .standard: 88; case .wide: 98; case .expansive: 108 } }
    var discoverInterestIcon: CGFloat { switch band { case .narrow, .standard: 21; case .wide: 25; case .expansive: 29 } }
    var discoverInterestIconFrame: CGFloat { switch band { case .narrow, .standard: 42; case .wide: 48; case .expansive: 54 } }
    var discoverWatermark: CGFloat { switch band { case .narrow: 70; case .standard: 82; case .wide: 96; case .expansive: 112 } }
    var discoverInterestTileHeight: CGFloat { switch band { case .narrow: 154; case .standard: 168; case .wide: 190; case .expansive: 210 } }
    var discoverTilePadding: CGFloat { switch band { case .narrow: 14; case .standard: 16; case .wide: 19; case .expansive: 22 } }
    var networkTileMinimumWidth: CGFloat { switch band { case .narrow: 132; case .standard: 145; case .wide: 170; case .expansive: 190 } }
    var networkTileMaximumWidth: CGFloat { switch band { case .narrow, .standard: 220; case .wide: 250; case .expansive: 280 } }
    var networkTileHeight: CGFloat { switch band { case .narrow: 150; case .standard: 164; case .wide: 184; case .expansive: 202 } }
    var networkLogoSize: CGFloat { switch band { case .narrow: 52; case .standard: 60; case .wide: 70; case .expansive: 78 } }
    var pagePadding: CGFloat { horizontalGutter }
    var playerArtworkMaximumWidth: CGFloat { switch band { case .narrow, .standard: 620; case .wide: 540; case .expansive: 500 } }
    var playerControlColumnMaximumWidth: CGFloat { 520 }

    var navigationFont: CGFloat { switch band { case .narrow, .standard: 15; case .wide: 18; case .expansive: 21 } }
    var navigationControl: CGFloat { switch band { case .narrow, .standard: 36; case .wide, .expansive: 44 } }
    var navigationTitle: CGFloat { switch band { case .narrow, .standard: 17; case .wide: 22; case .expansive: 28 } }
    var artwork: CGFloat { switch band { case .narrow, .standard: 44; case .wide: 52; case .expansive: 60 } }
    var rowSpacing: CGFloat { switch band { case .narrow, .standard: 12; case .wide: 14; case .expansive: 16 } }
    var primary: CGFloat { switch band { case .narrow, .standard: 15; case .wide: 17; case .expansive: 19 } }
    var secondary: CGFloat { switch band { case .narrow, .standard: 12; case .wide: 14; case .expansive: 15 } }
    var rowPadding: CGFloat { switch band { case .narrow, .standard: 6; case .wide: 9; case .expansive: 11 } }
    var markerWidth: CGFloat { switch band { case .narrow, .standard: 20; case .wide: 24; case .expansive: 28 } }
    var compactControlFont: CGFloat { switch band { case .narrow, .standard: 13; case .wide: 15; case .expansive: 17 } }
    var detailTitle: CGFloat { switch band { case .narrow, .standard: 22; case .wide: 26; case .expansive: 30 } }
    var detailBody: CGFloat { switch band { case .narrow, .standard: 13; case .wide: 15; case .expansive: 17 } }
    var detailsMediaMaximumWidth: CGFloat { switch band { case .narrow: 260; case .standard: 320; case .wide: 380; case .expansive: 440 } }
    var detailsMetaCardMinimumWidth: CGFloat { switch band { case .narrow: 130; case .standard: 145; case .wide: 170; case .expansive: 200 } }
    var detailsMetaKeyFont: CGFloat { switch band { case .narrow, .standard: 10; case .wide: 11; case .expansive: 12 } }
    var detailsGutter: CGFloat { switch band { case .narrow: 16; case .standard: 20; case .wide: 28; case .expansive: 36 } }
    var miniPlayerArtworkSize: CGFloat { switch band { case .narrow, .standard: 52; case .wide: 58; case .expansive: 64 } }
    var miniPlayerControlSize: CGFloat { switch band { case .narrow, .standard: 44; case .wide: 48; case .expansive: 52 } }
    var miniPlayerGutter: CGFloat { switch band { case .narrow: 14; case .standard: 18; case .wide: 26; case .expansive: 34 } }
    var miniPlayerSpacing: CGFloat { switch band { case .narrow, .standard: 8; case .wide: 10; case .expansive: 12 } }
    /// Extra scrollable space below Discover tile grids. The mini-player is
    /// presented in a safe-area inset, but this clearance lets the final row
    /// scroll fully above it instead of finishing against or beneath the bar.
    var discoverTileBottomClearance: CGFloat { miniPlayerArtworkSize + 32 }
    /// Lets the last station row scroll fully above the persistent mini-player.
    var stationListBottomClearance: CGFloat { miniPlayerArtworkSize + 32 }
}
