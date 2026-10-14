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
}
