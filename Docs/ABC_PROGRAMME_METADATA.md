# ABC programme metadata

Verified 25 October 2026.

Wireless now uses ABC's official website schedule service for all 68 ABC directory feeds that do not already use its music now-playing service. The existing 22 music feeds retain song title/artist metadata. Programme information follows the existing SEN/Tapt presentation: station name and current programme in Playing, with presenter, broadcast times and upcoming programmes in Details. Upcoming broadcasts remain visible between sport events.

## Sources and mapping

- ABC listen live pages and the JavaScript used by those pages identify the official `papiServiceId` and schedule query format.
- Schedule endpoint: `https://www.abc.net.au/core-next/api/schedule?service=LOCAL_MELBOURNE&date=2026-10-25&tz=UTC&ratio=1x1`.
- ABC's [schedule help](https://help.abc.net.au/hc/en-us/articles/360001148215-How-can-I-access-the-latest-ABC-radio-schedules) identifies its station websites as schedule sources.
- Pilbara uses `LOCAL_NORTHWESTWA`; Wimmera uses `LOCAL_WESTERNVIC`. These were verified against their official live pages and the stream URLs returned by ABC's now-playing endpoint.
- Radio National's regional identifiers remain separate. `RN_VIC` and `RN_TAS` currently return empty schedules, so these two eastern-time services fall back to `RN`, the national eastern schedule. This is a Wireless fallback, not a claim that ABC supplies regional listings. QLD, SA, NT and WA retain their own timed schedules.
- Radio Australia uses `RA` for the directory's English `raeng` feed. Sport uses each feed's service identifier, including separate rapid feeds. Missing event listings do not produce a placeholder or an expired programme.

Autohop was inspected before implementation; it has no equivalent live-radio schedule provider. Wireless's existing ProgrammeGuide was extended directly.

## Refresh and failure behaviour

The guide loads yesterday, today and tomorrow in UTC, decodes absolute start/end timestamps and selects the current programme locally. ABC's formatted clock labels and cached `onNow` flags are not used to select programmes. The guide reevaluates every minute and refreshes schedule data every five minutes. Presenter names are optional. Repeated entries are deduplicated by service, programme identifier and start time. Cancelled station requests cannot apply to a newly selected station. Failed refreshes clear expired current programmes.

Times describe live broadcasts; TV Sync delay does not shift the programme schedule. No new Lock Screen or CarPlay programme projection was added. Source availability does not establish physical-device playback.

## Directory audit

The same research pass checked all 90 live ABC directory records for programme/music coverage. Two well-supported website corrections were applied to production D1 using version guards, preserving audit-log entries and a local before snapshot:

- ABC Coffs Coast: replaced a generic stream-help page with its official live page.
- ABC South West WA: replaced the unrelated Wheatbelt page with its own official live page.

Both corrections were verified through the live API at catalogue revision 874. No ACMA licence records were researched or identified in this pass. Complete coverage evidence, before/after snapshots and the applied SQL are retained privately under `station-directory/research/abc-programmes-2026-10-25/`.

## Validation

- Decoded 628 programme entries from the retained official responses.
- Live end-to-end ProgrammeGuide requests succeeded for Melbourne, RN WA, RN Victoria's fallback, NewsRadio, Radio Australia and Grandstand. Grandstand correctly returned an upcoming broadcast with no current programme at the time of the check.
- iPhone 18 Pro simulator unit suite: 66 tests, one skipped, zero failures. New tests cover absolute timestamps, overnight programmes, presenters, repeated identifiers, invalid/empty entries, regional identifiers, the RN fallback and stopping the guide.
- Unsigned Release build for generic iOS succeeded.
- In-app Support and SUPPORT_GUIDE.md updated. Physical-device and visual UI validation were not performed for this change.
