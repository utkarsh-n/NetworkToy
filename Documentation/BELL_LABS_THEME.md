# SnoopyNet's 1984 archive

The explicit visual direction is a 1984 Bell Labs / AT&T instrument room. This is a historical theme around the existing modern internet model. It does not change protocol behavior, traffic calculations, payload units, routing, or architecture. In particular, QUIC, TLS 1.3, and contemporary wireless systems must not be described as technologies available in 1984.

The optional archive uses `BellArchive` and `BellArchiveItem` in `NetworkToy/App/BellArchive.swift`. All humorous captions are original fictional copy, not historical quotations, advertisements, or company slogans. Historical names are text labels; the archive supplies no reproduced company logos.

## Historical grounding

The local telephone divestiture took effect on January 1, 1984. The seven regional holding companies were commonly called Baby Bells. The [Federal Judicial Center's court history](https://www.fjc.gov/node/11371686) gives that implementation date. A contemporary FCC rule in the [October 18, 1984 Federal Register](https://archives.federalregister.gov/issue_slice/1984/10/18/40810-40876.pdf), printed page 40859, footnote 5, also identifies January 1, 1984.

The original seven names are listed in the [January 10, 1984 Federal Register](https://www.govinfo.gov/content/pkg/FR-1984-01-10/pdf/FR-1984-01-10.pdf), printed page 1191, footnote 3. Display names use their familiar brand forms:

| ID | Display name | Illustrative map anchor |
| --- | --- | --- |
| ameritech | Ameritech | Chicago |
| bell-atlantic | Bell Atlantic | Philadelphia |
| bellsouth | BellSouth | Atlanta |
| nynex | NYNEX | New York |
| pacific-telesis | Pacific Telesis | San Francisco |
| southwestern-bell | Southwestern Bell | St. Louis |
| us-west | U S WEST | Denver |

Anchor cities and broad region labels are presentation choices. They are not assertions about exact headquarters, geographic service polygons, or actual internet exchanges. They must not replace the modern simulation's synthetic network nodes or influence its pathfinding.

[AT&T's official brand history](https://about.att.com/innovation/intellectualproperty/ip_brands/ip_history.html) describes its retained long-distance, manufacturing, and research businesses. [Nokia Bell Labs' own history](https://www.nokia.com/bell-labs/about/history/) explains that Bell Labs continued at AT&T while a staff group formed Bellcore for the independent operators. This distinction avoids implying that research stopped at divestiture.

## Integration notes

- Apply the final user direction throughout the app: dark mode for the console, native navigation, tuning, trace, guide, archive, and packet sniffer. Use the current dark blue `NetTheme` grounds, readable ink, and signal accents consistently across those surfaces.
- CRT scanlines and phosphor glow supply the instrument character. Keep controls, status, packet information, units, and precision readable over those effects.
- Project the striped globe as a sphere. Rotate its stripes, geography, nodes, links, and packet positions together through the same globe projection so their spatial relationships remain aligned during interaction.
- `BellArchive.items` supplies seven stable identities, names, broad regions, city coordinates, and original one-liners (`originals` is an alias).
- `BellArchive.dateLabel` is `01 JAN 1984`; `intro` supplies the short historical introduction. `date`, `stamp`, `title`, `subtitle`, `summary`, and `retained` supply other reading copy.
- Show `modernModelNote` when historical branding could make the era of the simulation ambiguous.
- Show `mapNote` beside any historical globe/map. Mark that map as an archive illustration, separate from a packet route.
- `BellArchive.sources` supplies exact external source URLs and descriptions. Source links are user-initiated and do not imply simulation traffic is real.

These notes record the visual direction and integration requirements. Build, UI, and physical-device evidence belongs in `Documentation/VERIFICATION.md`.

Research checked October 13, 2026. The AT&T and historical Federal Register fetches exceeded the browsing tool's timeout/size limits; their indexed source text supplied the cited passages. The Federal Judicial Center and Nokia Bell Labs pages were also opened directly. The archive summarizes fewer than 200 source-derived words per source across its copy and this note.
