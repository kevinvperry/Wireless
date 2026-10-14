# Contributing to Wireless

Wireless is a native Swift and SwiftUI Australian live radio player for iPhone, iPad and compatible Mac use. Contributions should target the `Wireless` iOS app and its supporting catalogue service.

## Before changing code

Read [AGENTS.md](AGENTS.md), the [design contract](DESIGN.md), [page reference](PAGES.md) and [testing guide](MOBILE_TESTING.md). Use Australian English. Follow existing navigation and accessibility patterns. Where an equivalent Autohop implementation is available, review and adapt it with its attribution and licence intact; an Autohop checkout is not needed to build Wireless.

Keep changes focused and explain the problem, resulting behaviour and validation. Update both the support source and in-app support when behaviour changes. Report build, simulator and physical-device results separately; do not imply that compilation proves playback quality.

## Issues and station corrections

Search existing issues first. Include the app version, device/OS, reproducible steps and expected versus actual behaviour. For station corrections, provide the station name, affected metadata or stream, and an authoritative public source. Explain conflicting evidence instead of guessing classifications. A contributor can propose a correction without production access; maintainers apply verified directory updates with an audit trail.

Do not attach production database exports, passwords, session cookies, private account details or unredacted diagnostics. Report security issues privately using [SECURITY.md](SECURITY.md).

## Pull requests

- Build the Wireless scheme and run checks relevant to the change.
- For interface changes, check comparable screens and include suitable screenshots with personal information removed.
- For catalogue-service changes, run `npm run check` and `npm test` in `station-directory` using your local configuration.
- Preserve existing third-party notices. Original contributions use the project's MIT licence; changes to `Wireless/VocalBoost.swift` retain MPL-2.0.
- Do not commit signing material, local deployment configuration, database copies, raw research or generated imports. See the [public-content policy](Docs/PUBLIC_CONTENT_POLICY.md).

Discuss substantial changes in an issue before implementation. Maintainers may ask for physical-device checks where simulator coverage is insufficient.
