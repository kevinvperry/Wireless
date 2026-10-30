# Shazam screens and local history — 31 October 2026

The recognition page now uses Wireless's purple glass controls, a dark gradient
backdrop, larger responsive artwork, and shared song details/actions. Artwork uses
available container width up to 420 points in a single column, rather than the
previous fixed 200 points. Wider containers use artwork and details side by side;
accessibility text sizes keep a scrollable single column. Ready, listening,
no-match and error states use a glass status card. Reduced Motion disables the
pulsing emblem. The privacy explanation is expandable; a separate-connection
notice remains visible whenever the capture fallback is in use.

## History ownership and behaviour

`MobilePlayer` owns the shared main-actor `ShazamHistoryStore`. Only a successful,
current recognition callback records an entry, with the attempt UUID as its stable
identity. A repeated callback for that identity cannot add a second entry. Separate
identifications of the same song remain separate dated events. Records include
title, artist, artwork/music/Shazam URLs, station identity/name and identification
time; no PCM or fingerprints are stored. Results still do not replace broadcaster
metadata or write to the external Shazam library.

History is available from the recognition sheet's History control and from
Settings → Shazam History, including while playback is paused. It has newest-first
date groups, song/artist/station search, shared full song details with both links,
individual deletion and confirmed clearing. Native alerts provide explicit Cancel
and destructive actions on phone and iPad. Going into history and back preserves
the current result. Recognition teardown belongs to the containing sheet's
onDismiss (and its Close button), not navigation within the sheet.

The store adapts Autohop's ListeningHistoryStore main-actor ownership, newest-first
sorting, atomic Application Support writes and refusal to overwrite after a failed
load. Podcast progress batching, CloudKit and sync envelopes are not needed here.
Wireless writes a versioned JSON document at Application Support/Wireless/
shazam-history.json. A failed mutation preserves the in-memory entries and reports
an error; an unreadable or newer-version file is preserved and blocks writes while unreadable. Reads are retried on opening history or before
the next save, so temporary protected-file access failures can recover without
erasing earlier entries. Explicit clearing can reset history. History is local to this device, with no automatic trimming or
cross-device/Shazam sync. Older recognition results cannot be recovered from app
history because previous releases did not store them.

## Validation

- Full unit suite: 112 tests, one existing skip, zero failures. New store tests
  cover round-trip metadata/links, station/date ordering, callback identity,
  repeated-song events, removal/clear, unreadable-file preservation and failed
  writes that must not pretend to save or delete entries. A subsequent focused
  run passed all four store tests, including recovery from a temporarily failed
  load without overwriting recovered entries.
- iPhone 18 Pro Max checks passed for result/error/listening states, largest text,
  and navigating into history and back without clearing the result.
- Smaller iPhone 17e and iPad mini checks passed for largest-text result actions,
  history search, opening song details, cancelling clear and confirmed clearing.
  iPad detail layout also exercises the wider container arrangement.
- Unsigned iPhone Release and compatible Mac builds passed. No physical-device
  installation, archive or upload was performed. Physical recognition performance
  and actual external music-app hand-off were not revalidated by these UI checks.
- Preview screenshots are under build/ShazamDesignPreviews (ignored build output).
  The isolated DEBUG fixture uses public artwork from Apple's album page:
  https://music.apple.com/us/album/get-the-knack/1452360997
  Production continues to use only the artwork URL returned with each match.

Autohop's PlayerView glass styling and ListeningHistoryStore were inspected before
implementation. Existing Wireless native glass treatments were reused rather than
adding another design system. Both Support guide sources describe the new history
and its local-only scope.
