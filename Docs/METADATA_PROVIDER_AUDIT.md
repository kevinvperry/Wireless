# Metadata provider audit

Audit date: 17 October 2026 (Australia/Melbourne).

## ABC music services

Wireless checked the ABC's public `musicNowPlaying` service and received valid responses for these identifiers:

- ABC Classic — `CLASSIC`
- ABC Classic 2 — `CLASSIC2`
- ABC Country — `COUNTRY`
- ABC Jazz — `JAZZ`
- ABC Kids listen — `KIDSLISTEN`
- Double J — `DOUBLEJ`
- triple j — `TRIPLEJ`
- triple j Hottest — `H100`
- triple j Unearthed — `UNEARTHED`

The live Wireless directory already contained these services with official ABC audio endpoints. No directory correction was required during this audit.

## SCA and LiSTNR

The official LiSTNR web player obtains station identifiers from its public GraphQL directory at `https://api.listnr.com/v2` and subscribes to `wss://ws.nowplaying.listnr.com/station` using the selected stream's call sign. Wireless retains this companion path for LiSTNR stations and the `Music` sub-networks belonging to Triple M and Hit.

Triple M and Hit `Metro` and `Regional` broadcast stations now deliberately use metadata embedded in the selected audio stream. They do not start a LiSTNR companion connection, because sustained diagnostics showed that embedded song changes were timelier and more complete while LiSTNR often returned an empty current track and repeatedly reconnected. A missing Triple M or Hit sub-network also defaults to embedded metadata rather than enabling LiSTNR from the hosting domain alone.

`Asset Link`, `Asset Spot` and `Asset Stop` values are temporarily accepted and displayed. They remain classified as technical markers in diagnostics, but are not filtered while embedded SCA song delivery is re-established and measured. This supplies a clean baseline before narrower filtering is designed.

The earlier expanded comparison found 224 music-focused Wireless records using official LiSTNR HLS streams, and every one matched a current call sign in the official LiSTNR directory. That inventory remains useful evidence, but a matching call sign is no longer sufficient to enable the companion provider for an SCA broadcast station. Two LiSTNR-hosted records classified as News remain excluded.
