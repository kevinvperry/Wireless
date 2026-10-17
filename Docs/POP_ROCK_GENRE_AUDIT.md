# Pop and Rock genre refinement audit

Audit date: 15 October 2026

## Scope

The live directory contained 119 published stations with the primary genre **Pop** and 66 with **Rock**. This audit reviewed all 185 records using their broadcaster, network, website, station descriptions and existing first-party music tags.

The audit keeps broad labels where a station has a mixed format or the available evidence does not support a narrower primary genre. Secondary tags remain unchanged so the directory retains details such as decade, mood and overlapping styles.

## Controlled genres added

| Genre | Use |
| --- | --- |
| Classic Rock | Rock favourites and anthems from earlier decades |
| Contemporary Hits | Current chart hits and recent mainstream favourites |
| Heavy Metal | Heavy metal, hard rock and related heavier styles |
| K-Pop | Korean pop and closely related Asian pop music |
| Soft Rock | Softer rock, adult-oriented rock and melodic favourites |

Existing controlled genres were reused where they were a better fit: Australian Hits, Classic Hits, Folk & Acoustic, Indie & Alternative, and Kids & Family.

## Results

- 75 stations moved from Pop to Contemporary Hits. These include the Hit Network, KIIS, the current-hit Nova services, ARN Star and Power FM services, supported ACE stations and current-chart digital services.
- 46 stations moved from Rock to Classic Rock. These consist mainly of Triple M services carrying broadcaster-supplied Classic Rock and Classic Hits tags, plus Triple M Classic Rock and The Sound.
- Triple M 90s, Triple M 2000s, Brit Rock Essentials, Essential Emo and Grunge moved to Indie & Alternative.
- Hard N Heavy and Heavy AF moved to Heavy Metal.
- K-Pop and SBS PopAsia moved to K-Pop.
- Almost Acoustic moved to Folk & Acoustic; Aussie Pub Rock moved to Australian Hits; Kids Hits moved to Kids & Family; Soft Rock moved to Soft Rock.
- Guilty Pleasures, Star 92.1 and Totally Radio – Greatest Hits moved to Classic Hits.
- 38 Pop and 10 Rock stations remain in their broad genres because their formats span eras or styles, or first-party evidence did not justify a narrower category.

## Principal sources

- [ARN network formats](https://arn.com.au/network/) identifies its regional Contemporary Hit Radio and Hot Adult Contemporary brands.
- [LiSTNR music stations](https://play.listnr.com/network/listnr/music-stations) supplies station names, descriptions and music tags for LiSTNR, Hit and Triple M services.
- ACE station websites identify Edge FM as Today’s Best Music, Mixx FM as hits-led and TRFM as a current and feel-good hits service.
- Individual official station websites were reviewed for the remaining commercial services.

## Audit trail and validation

The live changes use version-guarded updates. Each changed record receives a `station.music-genre-audited` event containing the previous and new primary genre, retained music tags, source and rationale. The completed audit also advances `catalogue_meta.revision`, which makes existing Wireless installations replace older cached catalogues. The reviewed assignment SQL is retained privately because it contains production record identifiers and database versions.
