# Nightwatch v0.2 — Dark-sky sites: design spec

Date: 2026-09-23
Status: approved design, pre-implementation
Owner: rsutcliffe
Builds on: `2026-09-23-nightwatch-design.md` (v0.1, shipped)

## 1. Purpose

Show the user dark-sky observing sites within a radius they choose, with tonight's conditions at each, so they can decide whether a short drive buys a better sky than home.

Success criteria:

1. With a site set and a radius of 50 km, the Targets window's "Dark sites" group lists every bundled certified place within 50 km plus up to five computed dark spots, sorted by tonight's score, each with distance, bearing, darkness label and clear window.
2. When a listed site's score beats the home site's by 20 or more, the popover shows one line naming it, its distance and its clear window; otherwise nothing.
3. "Use as beat" on a card saves the site and makes it the active site; the whole app recomputes for it.
4. Radius and unit (km or miles) are user settings; changing them updates the list within one refresh.
5. All of this works offline once the bundled data and the last forecasts are cached; nothing needs a key.

## 2. Research basis (23 Sep 2026)

| Candidate | Finding | Use |
|---|---|---|
| DarkSky International list | HTML only, direct fetch returns 403, no reuse terms published | Not fetched; certification is cited as a public fact per place |
| UK Dark Sky Discovery Sites | Interactive uMap (umap.openstreetmap.fr map 718191) embedded on darkskydiscovery.org.uk; its "Milky Way Class" and "Orion Class" layers are published CSVs with name and coordinates; no terms | Hand-curated entries with a source URL each (checked 24 Sep 2026) |
| Wikidata | 39 items typed dark-sky preserve / International Dark Sky Reserve with coordinates (CC0); UK coverage one item | Seed list plus coordinates for hand-curated places |
| OpenStreetMap / Overpass | No dark-sky tags within 150 km of Sheffield; server returned busy errors | Not used |
| VIIRS Nighttime Lights annual composite (NOAA/NASA EOG) | CC BY 4.0 per EOG; download requires a free EOG account; GeoTIFF, 15 arc-second | Owner downloads once; a script derives a small bundled grid |
| David Lorenz light-pollution atlas | No public licence | Not used |
| Bortle from radiance | No defensible published mapping; Lorenz warns against it | Computed spots get a darkness band, never a Bortle class |

## 3. Decisions taken with the owner

| Topic | Decision |
|---|---|
| Definition | Certified places (DarkSky International parks, reserves, sanctuaries, communities; UK Dark Sky Discovery Sites) and computed darkest spots from a light-pollution grid |
| Radius | Default 50 km, range 5 to 300, unit km or miles per setting |
| Placement | "Dark sites" group in the target browser; one popover line when a site beats home; "Use as beat" to switch the active site |
| Forecast | Per-site Open-Meteo fetch for the nearest eight sites per refresh |
| Raster | Owner registers for a free EOG account and downloads VIIRS once; the derived grid is committed |

Rulings by the assistant: computed spots carry a darkness band from documented radiance thresholds, labelled as a heuristic, never a Bortle class; the certified list credits DarkSky International and Wikidata and is extensible by pull request.

## 4. Data

### 4.1 `Sources/SkyCore/Resources/darksky/certified.json`

Array of:

```json
{"id":"gb-northumberland","name":"Northumberland International Dark Sky Park","kind":"park",
 "country":"GB","latitude":55.30,"longitude":-2.30,"designated":2013,
 "bortle":2,"source":"https://en.wikipedia.org/wiki/Northumberland_National_Park","wikidata":"Q1195889"}
```

`kind` ∈ park, reserve, sanctuary, community, urban, discovery. `bortle` optional, only when the source states a measured class. Built by `scripts/build-certified.py`: (a) a Wikidata SPARQL query for instances of Q3457162, Q52216504, Q72114283 with coordinates (verified live, 39 items); (b) a hand-maintained `data/certified-curated.json` for UK and Ireland places with a source URL each, coordinates copied from the place's Wikidata item, or for `discovery` entries from the programme's own map layer. The bundled Discovery Sites are the 25 within 150 km of Sheffield on the programme's "Milky Way Class" and "Orion Class" layers, each sourced to the programme's map centred on the site. Every curated entry's certification must be visible on its cited source page; the script fails if an entry lacks a source. Attribution: "Certified by DarkSky International or the UK Dark Sky Discovery Sites programme. Coordinates from Wikidata (CC0)."

### 4.2 `Sources/SkyCore/Resources/lightpollution/gb.lpgrid`

A little-endian binary: 20-byte header (magic `LPG1`, float32 south latitude, float32 west longitude, float32 cell size in degrees, uint16 rows, uint16 cols), then rows × cols float32 upward radiance in nW/cm²/sr, NaN for no data; row 0 is the southernmost row. Produced by `scripts/build-lp-grid.py <viirs.tif> --bbox 49.8,-8.7,60.9,1.8 --cell 0.01 --smooth 7 --land ne_10m_land.geojson --out gb.lpgrid` from the VIIRS annual "average masked" GeoTIFF. The masked product stores unlit land and the sea as exactly 0, so without the two passes most of Britain ties at 0 and the darkest spots land on the search circle's rim or in the sea: `--land` (Natural Earth 10 m land, public domain) writes sea cells as NaN, and `--smooth 7` takes a NaN-aware 7 × 7 cell mean so a cell reflects the glow around it; `LPGrid.darkestSpots` breaks the remaining ties by distance. `--cell 0.01` snaps to a whole multiple of the source's 15-arc-second pixels, so the built UK grid is 1,332 × 1,260 cells at 0.00833° (about 0.9 km), 6.4 MB. Attribution: "Light-pollution grid derived from NOAA/NASA Earth Observation Group VIIRS Nighttime Lights annual composite, CC BY 4.0." Other regions: run the script; the app loads every `.lpgrid` in the folder.

### 4.3 Darkness bands (heuristic, documented in the About window)

| Radiance nW/cm²/sr | Band |
|---|---|
| < 0.25 | Very dark |
| 0.25 to 1 | Dark |
| 1 to 5 | Rural |
| 5 to 20 | Suburban |
| ≥ 20 | Bright |

These are the assistant's thresholds, chosen so that UK national-park cores read Very dark or Dark and city centres read Bright; they are not a published scale and the UI says so.

## 5. Architecture

### 5.1 SkyCore additions

| Module | Responsibility |
|---|---|
| `Geo` | Haversine distance (km), initial bearing (degrees and compass point), destination point; unit formatting |
| `DarkSites` | `CertifiedSite` (Codable), `bundledCertified()`, `LPGrid` loader and `radiance(at:)`, `darkestSpots(center:radiusKm:count:minSpacingKm:)` scanning grid cells within the radius, greedy pick of the lowest radiance with a spacing constraint; `DarkSite` (id, name, kind, coordinate, distanceKm, bearingDeg, band, bortle?, source) and `sites(near:radiusKm:)` merging both sources |
| `Planner` | unchanged; called per site |
| `Config` | `darkSites { radiusKm: Double = 50, unit: km|mi, enabled: Bool = true }` |

### 5.2 App additions

| Component | Responsibility |
|---|---|
| `Store` | After the home plan: `darkSites = DarkSites.sites(near: site, radius)`; for the nearest eight, fetch or reuse a cached forecast (`~/Library/Caches/Nightwatch/sites/<id>.json`, 30-minute gate, same `ForecastService`), plan each with the home rule, sort by score then distance; `bestAway` = the top site if its score ≥ home score + 20 |
| Targets window | Group "Dark sites": cards with name, kind glyph, distance and bearing in the chosen unit, band or Bortle, clear window and score; "Use as beat" button |
| Popover | One line under the verdict when `bestAway` exists |
| Settings | Radius stepper (5 to 300), unit picker, enable toggle |
| About | Attribution lines and the darkness-band note |

### 5.3 Failure handling

Missing grid file: computed spots omitted, certified places still listed. Per-site forecast failure: card shows "no forecast" and sorts last. More than eight sites in range: the rest are listed with distance and band only. Empty result: the group shows "No dark sites within N km".

### 5.4 Tests

Geo distance and bearing against known pairs (Sheffield to Edinburgh 306.6 km, bearing 339.6°); grid header parse and lookup on a hand-built 3 × 3 grid; darkest-spot selection respects radius and spacing; band thresholds at the edges; certified JSON decodes and every entry has a source; Store's bestAway threshold; unit formatting.

## 6. Out of scope

Driving time, terrain or horizon obstruction, live OSM data, Bortle for computed spots, sites outside the bundled grids, editing the certified list in the app.
