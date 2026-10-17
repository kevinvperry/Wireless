# Not Yet Categorised audit — batch 01

Audited 15 October 2026. Scope: the first 30 published records ordered by station name before this audit.

Each retained stream was re-requested and returned a current playlist or sustained audio bytes. Station identity was checked against the station’s official website or, where the website was unavailable, authoritative Australian broadcaster or regulator records. Historical decoded-audio evidence was retained; a successful HTTP response alone was not treated as proof of Australian station identity.

## Outcome

- 26 stations verified, categorised and given artwork.
- 4 stations archived and their streams removed from public results.
- All retained general community stations now appear under **Community & Specialist → Community**. Indigenous, religious, foreign-language, arts, radio-reading and commercial services use their more specific existing destinations.

| Archived record | Reason |
| --- | --- |
| 1079 Life | The endpoint referenced by the current official website player returned HTTP 404. The station may be restored when a working official stream is available. |
| 24-7 Romance | Current sources identify it as a United Kingdom service. |
| 3J Radio | Its official site publishes a Lebanese telephone number and provides no supportable Australian identity. |
| 420media | The audio stream works, but the only Australian claim is a self-entered directory label with no supportable Australian operator or location. |

The detailed field changes and source URLs are preserved in migration `0052_not_yet_categorised_audit_batch_01.sql` and audit-log entry `not-yet-categorised-batch-01-2026-10-15`.
