# Network genre audit — 14 October 2026

Wireless audited the 247 published stations in the ABC, ACE Radio Network, ARN, Heart, iHeart, SBS Audio, SEN, Super Radio Network, Tapt Media, Totally Radio and West Coast Radio catalogues. Official station and network pages were used as the primary evidence. The same pass also classified FIVEAA as News and the four dedicated Triple M live sports streams as Sport.

## Completed network coverage

| Network | Published | Assigned | Pending editorial choice |
| --- | ---: | ---: | ---: |
| ABC | 90 | 90 | 0 |
| ACE Radio Network | 21 | 21 | 0 |
| ARN | 37 | 37 | 0 |
| Heart | 3 | 3 | 0 |
| iHeart | 12 | 7 | 5 |
| SBS Audio | 8 | 8 | 0 |
| SEN | 37 | 37 | 0 |
| Super Radio Network | 20 | 20 | 0 |
| Tapt Media | 4 | 4 | 0 |
| Totally Radio | 12 | 12 | 0 |
| West Coast Radio | 3 | 3 | 0 |
| **Total** | **247** | **242** | **5** |

The completed classifications use the controlled primary-genre field. The audit added News, Sport, Kids & Family and Christmas to the dropdown. Highlights include ABC Local Radio and Radio National under News; ABC Sport and every SEN service under Sport; ABC Kids listen under Kids & Family; ABC Classic and Jazz under Classical & Jazz; triple j and Double J under Indie & Alternative; SBS language news services under News; SBS PopAsia under Pop; SBS Radio 4 and SBS South Asian under World Music; and Elf Radio under Christmas.

## Pending editorial choices

The mixed heritage services were assessed individually. 2AY, 2QN, 2BS, 2HD, 2SM and Radio 97 are grouped under News because their official positioning and schedules are led by news, talk, sport and local information. 3CS, 3HA, 3SH, 3WM, 3YB FM, 2DU, 2GF, 2HC, 2LM, 2MG, 4AM and 4KZ are grouped under Classic Hits because familiar music is central to their official daily offering despite their substantial spoken programming.

Five iHeart branded streams also remain unassigned pending a consistent editorial rule: Chemist Warehouse Remix, Club Lime Radio, Plus Fitness Radio, Woolworths Radio and ZooFit. Their broad upbeat playlists could reasonably be grouped as Pop; the fitness services could instead be treated as Dance & Electronic.

## Audit trail

Migration `0043_expand_primary_genres.sql` adds the new controlled values. Every applied station assignment has an optimistic version guard and a corresponding `station.primary-genre-audited` event containing its evidence URL. The full decision record and guarded data SQL are retained outside the public repository because the working database material includes private operational data.
