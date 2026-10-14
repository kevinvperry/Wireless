# Wireless interface audit against Autohop

Audited 10 October 2026 against the current Autohop `PlayerView`, `QueueSheetView`, `PodcastsView` and `AdaptiveLayout` sources.

| Wireless element | Autohop reference | Applied contract |
| --- | --- | --- |
| Player navigation buttons | Player top bar | 36-point phone and 44-point wide controls; 15/18/21-point semibold symbols |
| Playing and Sync tabs | Player panel selector | Selected icon and semibold label in a neutral glass capsule; unselected icon only |
| Player artwork | Now Playing artwork | Available width minus 44 points, 20-point corner radius and purple ambient glow |
| Programme/station copy | Episode copy | 16-point bold primary and 12-point regular secondary text |
| Live/delay bar | Player scrubber | Five-point purple track, 22-point white thumb and 13-point semibold rounded labels |
| Play/Pause | Player transport | 76-point purple glass circle with a 28-point regular symbol |
| Player utility actions | Player audio row | 44 × 32-point glass controls with 18-point bold purple symbols |
| Sheet title and close control | Up Next | Inline bold title and adaptive 36/44-point close control |
| Favourite rows | Up Next rows | Adaptive 44/52/60-point artwork; 15/17/19-point bold primary and 12/14/15-point secondary text |
| Favourite position marker | Up Next rank marker | Adaptive 20/24/28-point column with bold monospaced secondary text |
| Discover station rows | Autohop list rows | Same artwork, spacing, primary, secondary and vertical-padding bands as Favourite rows |
| Sync heading and introduction | Player Details hierarchy | Adaptive 22/26/30-point bold heading and 13/15/17-point body text |

`WirelessLayoutMetrics` is the single source for matching adaptive measurements. Width bands mirror Autohop: narrow below 340 points, standard below 500, wide below 700 and expansive at 700 or more.

The remaining larger Sync delay value is intentionally a primary numeric readout rather than a matching Autohop text element. Native controls such as Toggle, Slider, Form, TextField and system navigation retain Apple’s platform typography and Dynamic Type behaviour.

On iPhone, the app declares portrait as its only supported interface orientation. iPad declares portrait, upside-down portrait and both landscape orientations; compatible Mac windows remain resizable.
