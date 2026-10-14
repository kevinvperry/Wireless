# Wireless station directory

An optional Cloudflare Worker service that backs Wireless's station discovery. It provides a public read-only catalogue API, D1 storage and an authenticated browser editor with R2 artwork storage. Audio plays directly from broadcasters; the Worker does not relay it.

Building the iOS app does not require deploying this service or accessing production accounts.

## Local development

Use Node.js with npm and a version supported by the pinned Wrangler dependency.

```sh
cp wrangler.example.jsonc wrangler.jsonc
npm ci
npm run db:migrate:local
npm run dev
```

The local catalogue starts empty. Use a local editor account and add a test station through `/admin/`. Provision that account with `node scripts/provision-user.js --local`, supplying JSON on standard input with `email`, `display_name`, `password` and `role`. Use a local test identity and a unique password; never save credentials in source control or pass them as command-line arguments. Valid roles are `editor` and `admin`. Passwords require at least 14 characters and no more than 72 UTF-8 bytes.

The example configuration contains placeholder resource identifiers. For deployment, create your own Cloudflare Worker, D1 database and R2 bucket, then configure your ignored `wrangler.jsonc`. The maintainer's production configuration and credentials are not distributed. Review migrations before applying them to any remote database.

## Checks

```sh
npm run check
npm test
```

The integration suite uses Miniflare and synthetic accounts/stations. It checks authentication, roles, CSRF protection, catalogue editing, publication boundaries, stream inspection, artwork operations, concurrency, caching and account/session changes. These checks do not certify live station audio or physical-device playback.

## Public API

- `GET /api/v1/catalogue`: schema version, catalogue revision and update timestamp.
- `GET /api/v1/stations`: published stations and enabled stream alternatives.
- `GET /api/v1/stations/:id`: one published station.
- `GET /api/v1/filters`: available networks, states, cities and counts.

Station queries support `q`, `network`, `state`, `city`, `page` and `page_size` (default 50, maximum 100). Responses include revision and pagination metadata. Station records expose descriptive metadata, public contact information and stream alternatives with technical measurements when available. Private editorial notes, account data and audit records are excluded from the public API.

Clients should cache the last complete catalogue, use ETags and retain cached content after an error. If a multi-page download sees its catalogue revision change, restart it instead of combining versions. Offline browsing does not provide offline audio.

## Editing and stream checks

Editors manage station metadata, streams and artwork. Administrators also manage accounts. Draft and archived stations are excluded from public results. The editor supports alternative streams, preferred-stream selection, shared artwork, duplicate merging and an audit trail; conflicting saves are rejected.

New or changed streams trigger a bounded technical inspection. It follows redirects and supported playlists, samples audio headers and records format, codec, bitrate, channels and related playback evidence. Changing URLs or request headers clears old verification. A technical check does not establish station identity, subjective quality, sustained availability or licensing rights.

Artwork uploaded by an operator is served from their configured R2 bucket. Downloaded broadcaster logos are not bundled with the public source. Only upload assets you are entitled to use.

## Imports and operations

The `import:*` scripts and `db:seed:local` command are optional maintainer tools. They depend on separately held research files and generated SQL; those inputs are not part of the public source and are not prerequisites for local development or tests. `Scripts/ValidateDiscoverRegions.swift` in the parent project can use the retained curated capital-city reference with a separately supplied catalogue-stations JSON array.

The public migrations contain schema and generic state normalisation only. Production data-correction migrations are held privately because some retain complete station snapshots and editorial history. Keep their private audit trail; publish separately reviewed factual summaries when appropriate. Keep production exports, user/session records, private editorial notes, raw research, generated imports and local deployment configuration outside it. Existing import scripts preserve editor-modified records; always review generated SQL before applying it. Back up a database privately before maintenance. Deploying an older Worker does not undo database changes.

The editor uses same-origin requests, CSRF tokens, secure HttpOnly cookies, expiring sessions, forced initial password changes and login throttling. Public endpoints allow cross-origin reads without credentials. See the repository [security policy](../SECURITY.md) for reporting concerns.
