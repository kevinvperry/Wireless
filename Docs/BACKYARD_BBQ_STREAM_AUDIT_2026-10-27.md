# Backyard BBQ higher-bitrate stream investigation — 27 October 2026

## Result

No working higher-bitrate Backyard BBQ stream was found among 28 distinct URL combinations. Retain the existing preferred HLS stream. This is a bounded investigation of likely patterns, not proof that a private or differently named higher-rate feed cannot exist.

LiSTNR's current [Backyard BBQ page](https://play.listnr.com/station/backyard-bbq) publishes:

`https://sa47.scastream.com.au/live/backyard-bbq.stream/playlist.m3u8?dist=listnr-web`

Its master playlist advertises one 65,000-bit/s HE-AAC rendition. The station name, description and website match Wireless's directory record. The station page's internal station code is `backyard-bbq`; its listed audio stream has call sign `BACKYARD-BBQ`. No second audio stream was listed in the inspected station data.

## Decoded measurements

| Stream | Short-sample packet bitrate | Decoded format |
| --- | --- | --- |
| Published Backyard BBQ HLS | 65.3 kbps | HE-AAC, 44.1 kHz, stereo |
| Derived direct `/backyard-bbq` AAC | 65.4 kbps | HE-AAC, 44.1 kHz, stereo |
| Rock ’n’ Road Trip `_128` HLS, positive control | 130.2 kbps | AAC-LC, 48 kHz, stereo |

The first HLS sample decoded 5.016 seconds; the direct sample decoded 14.025 seconds. A separate repeat decoded three further HLS segments totalling 12.816 seconds. Their measured packet bitrates varied from 41.4 to 48.1 kbps, so 65 kbps is the advertised rendition rate, not a guarantee of constant instantaneous bitrate. Adding quality parameters also decoded approximately 65 kbps audio.

These are codec/transport checks, not subjective listening comparisons or prolonged-availability certification. The profiles differ between Backyard BBQ and the control: bitrate alone does not measure their relative audible quality. No recordings were retained; decoding used in-memory samples.

## URL experiments

The first set tested these mount names on both `sa47.scastream.com.au` and `sa46.scastream.com.au`, using `/live/<mount>.stream/playlist.m3u8?dist=listnr-web`:

- `backyard-bbq`
- `backyard-bbq_128`
- `backyard-bbq_256`
- `backyardbbq_128`
- `7backyardbbq_128`
- `7backyard-bbq_128`
- `7bbq_128`
- `7backyardbbq`

That is 16 combinations. Eight direct AAC mount alternatives on `sa47` used those same names. Two additional HLS filenames were tried on the published mount: `playlist_128.m3u8` and `index.m3u8`. Finally, HLS and direct AAC were each checked with `quality=high&bitrate=128`.

Total: 28 Backyard BBQ URLs, plus the separate Rock ’n’ Road Trip control. Four Backyard BBQ URLs decoded: the current HLS and direct mount, and those same two with quality parameters. All remained in the same advertised/observed bitrate tier. The other 24 candidates failed with HTTP 404 when resolving the actual playlist or requesting the direct mount.

The server frequently returns HTTP 200 and a synthetic master playlist for a nonexistent HLS mount. Following its session-specific media-playlist URL then returns 404. Initial status alone must not be counted as a working stream. The published master had one rendition; there was no higher HLS variant to select. The extra quality parameters did not increase its advertised bandwidth.

The comparison catalogue also contains newer names such as Pool Party and Pop 101 at approximately 64–65 kbps, alongside older `7…_128` feeds around 130 kbps. The higher-bitrate pattern therefore does not apply to every LiSTNR station.

## Live directory audit

Station: `station_39032c259d72`.

- Verified current identity, website, description and published stream against LiSTNR's page; no supported descriptive correction was needed.
- Retained the preferred HLS stream ID and every stream URL/enabled state.
- Refreshed HLS verification evidence.
- Corrected the existing direct AAC alternative from unverified to audio-decoded, adding measured bitrate, 44.1 kHz sample rate and two channels.
- Preserved the before snapshot, all probe results, source metadata, scripts and version-guarded SQL privately in `station-directory/research/backyard-bbq-2026-10-27/`.
- Rehearsed the SQL against the real snapshot locally and verified that a stale station version is rejected.
- Applied the guarded update to production D1, advancing station version 6 to 7 and catalogue revision 875 to 876, with a matching `station.streams.verified` audit entry.
- Verified the refreshed stream measurements and unchanged preferred stream through the live public API.

No station classification or licensing changes were made, and no ACMA licence record was researched or identified. No app rebuild or App Store Connect upload is needed for this directory verification update.
