# Public repository content

The public source should explain what Wireless does, how to build it, how to contribute and how its components fit together. It should not expose the maintainer's operational records.

| Material | Treatment |
| --- | --- |
| App and catalogue-service source, synthetic tests and dependency lockfiles | Public |
| README, contribution/security guides, design/page contracts and user support | Public; keep accurate and remove local-machine instructions |
| MIT licence, MPL text, attribution and third-party notices | Public |
| Schema and generic normalisation migrations | Public; never include credentials or private editorial records |
| Production data-correction migrations and merge archives | Private audit trail; publish only separately reviewed factual summaries |
| Curated capital-city ordering reference and validation fixture | Public; factual development reference, not a licence for broadcaster assets |
| Raw research, scraped responses, database-derived audits and generated imports | Private working material; publish only a separately reviewed, redacted summary when useful |
| Production database exports, editor/session data, password hashes and private notes | Private, outside source control |
| Cloudflare deployment identifiers/configuration and provisioning details | Private operator configuration; provide a public example |
| Signing keys, profiles, credentials, environment files and local build state | Private/ignored |
| Internal TestFlight checklists, upload evidence and device diagnostics | Private; create separate public release notes when releasing |
| Broadcaster artwork and bulk third-party datasets | Excluded pending an explicit redistribution review |
| Screenshots | Publish only reviewed current-app images without personal data; third-party artwork still requires review |

## History matters

The public repository starts from a reviewed source snapshot. Earlier operational history is retained in a separate private repository.

Ignore rules and a deletion commit affect the current tree only. Previously committed research, configuration, artwork and internal records remain accessible in Git history. A visibility change exposes that history too.

Before publication, prepare a reviewed clean source snapshot or an explicitly approved history rewrite, and check every branch, tag, release attachment, pull request and other repository surface. Keep a private backup before replacing history. Do not switch the existing repository to public while excluded material remains reachable.

The audit and private originals are maintained outside this repository. A pattern-based secret scan is one check, not proof that every sensitive record has been found.
