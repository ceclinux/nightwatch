# Nightwatch — design spec

Date: 2026-09-23
Status: approved design, pre-implementation
Owner: rsutcliffe
Licence: MIT (code). Hobby, non-commercial use assumed for data-source terms.

## 1. Purpose

A silent macOS menu-bar app that tells an amateur astronomer when tonight (or tomorrow night) will be clear enough, for long enough, to run a multi-hour imaging session, and what is worth pointing at. It notifies; it does not nag. It runs on any Mac the user builds it on and imposes no telescope brand.

Success criteria:

1. On a night that meets the go rule, the user receives a heads-up before sunset and a nudge 30 minutes before the clear window opens, without opening the app.
2. If the forecast turns, the user receives a cancel notice.
3. Opening the popover shows tonight's verdict, the clear window, key conditions and the three best targets in under one second, offline or online.
4. The target browser lists what is observable during the window, grouped by phenomenon, with a thumbnail per object and a "fits frame" badge relative to the user's field of view.
5. Same repo builds and runs on the user's MacBook, Mac mini and iMac with one command and no Apple Developer account.

## 2. Research basis (23 Sep 2026)

Existing tools: Transit (Mac Observatory) is the only native macOS menu-bar notifier found; it covers planets, Moon and satellites, not deep sky, and is closed source. Ouranos, Scope Nights, Astrospheric, DarkScout are iPad binaries on Apple silicon with no menu bar. Open-source planners (Nebulis, NightSeek, MyAstroBoard, DarkHours) are web or self-hosted. No open-source, telescope-agnostic, Mac-native background notifier with a phenomenon-grouped thumbnail browser exists.

Data sources selected (all keyless, attribution-only):

| Need | Source | Terms |
|---|---|---|
| Hourly cloud low/mid/high/total, dew point, wind, visibility, up to 16 days | Open-Meteo | CC BY 4.0, non-commercial free tier, attribution "Weather data by Open-Meteo.com" |
| Seeing, transparency, 72 h at 3 h steps | 7Timer ASTRO | Free for non-commercial use, author asks to be notified |
| Sun/Moon rise-set, twilight, planets, Moon phase, eclipses, conjunctions, alt/az | Astronomy Engine (C source) | MIT, no data files |
| Deep-sky catalogue | OpenNGC + addendum | CC BY-SA 4.0 |
| Constellation names, centres and stick figures | d3-celestial `constellations.json` and `constellations.lines.json` (GeoJSON, RA in degrees −180..180) | BSD-3-Clause; data derived from IAU pages |
| Thumbnails | CDS hips2fits, DSS2 colour | CDS acknowledgement; DSS copyright notice displayed |
| Comet elements | Minor Planet Center cometels.json.gz | MPC acknowledgement |
| ISS orbital elements | CelesTrak GP JSON, CATNR 25544 | Poll at most every 2 h; stop on non-200 |
| Meteor showers | Bundled JSON curated from IMO / IAU MDC | Cite IMO |
| Light pollution | User-entered Bortle class | None; no keyless API exists |

Excluded: Met Office DataPoint (decommissioned), Met Office DataHub, OpenWeatherMap, Meteoblue API, Astrospheric API (all keyed or paid), World Atlas 2015 (CC BY-NC, 2.9 GB).

Telescope calibration reference (not a dependency): DwarfLab DWARF Mini, 30 mm f/5, 150 mm focal length, frame about 2.1° × 1.2°. Presets are data, not code paths. Verified preset fields of view: DWARF Mini 2.1° × 1.2° (telescopicwatch.com review), DWARF 3 2.93° × 1.65° (skiesandscopes.com), Seestar S50 1.29° × 0.73° (seestar.com FAQ), APS-C DSLR at 200 mm 6.7° × 4.5° (computed from 23.5 × 15.6 mm).

Toolchain facts verified on the owner's Mac (macOS 27, Command Line Tools only, Swift 6.4): SwiftPM builds a SwiftUI `MenuBarExtra` executable plus the vendored Astronomy Engine C target; Swift Testing runs when the macro plugin path is passed (`-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`); XCTest is not available. SwiftPM resource bundles resolve through `Bundle.module`. On this SDK `@State` is a macro whose plugin (SwiftUIMacros) does not ship with the Command Line Tools, so views hold local state in `ObservableObject` view models via `@StateObject`; `@Published`, `@EnvironmentObject`, `@ObservedObject`, `@Environment` and `.task` all compile (verified 2026-09-23).

## 3. Decisions taken with the owner

| Topic | Decision |
|---|---|
| Location | CoreLocation auto-detect when permitted, manual named sites override |
| Platform | Native Swift, SwiftPM only, no Xcode, no WidgetKit in v1 |
| Licence and intent | MIT, hobby, non-commercial. 7Timer allowed |
| Thumbnails | hips2fits DSS2 colour cutouts at the user's FOV, fetched once, cached |
| Go rule default | At least 3 h contiguous with total cloud ≤ 25 %, inside astronomical darkness |
| Alerts | Evening heads-up derived from local sunset; tomorrow preview; 30 min pre-window nudge; cancel on downgrade; quiet hours 00:00–07:00 local |
| Groups in v1 | Nebulae, galaxies, star clusters, planets and Moon, events, constellations |
| Scope profile | Preset list or FOV width × height in degrees |
| Name | Nightwatch. Bundle id `io.github.rsutcliffe.nightwatch` |
| Flavour | Discworld City Watch references in naming and copy, optional |

Hemisphere and time zone: every "evening" or "night" boundary is computed from the ephemeris at the site's latitude, longitude and time zone. No fixed clock hours except the user-set quiet hours.

## 4. Architecture

One SwiftPM package, two products.

### 4.1 `SkyCore` (library, no UI, no AppKit)

Pure logic, fully unit-tested. Every module takes plain values in and returns plain values out. Network is abstracted behind a `Fetcher` protocol so tests use fixtures.

| Module | Responsibility | Depends on |
|---|---|---|
| `Forecast` | Fetch Open-Meteo and 7Timer, merge into `HourlyConditions[]` (cloud L/M/H/total %, dew point, temp, wind, visibility, seeing 1–8, transparency 1–8). 7Timer 3 h steps are held, not interpolated. | Fetcher |
| `Ephemeris` | Thin Swift wrapper over Astronomy Engine C target: sun/moon events, twilight, planet RA/Dec and alt/az, Moon phase and illumination, angular separation, eclipses, conjunctions, constellation for a point. | `CAstronomyEngine` |
| `Catalog` | Load bundled OpenNGC CSV and addendum into `[DeepSkyObject]` (id, names, type, RA, Dec, major/minor axis arcmin, magnitude, constellation). Map OpenNGC type codes to groups. Load constellation names and line segments. | none |
| `Events` | Meteor showers from bundled JSON (name, active range, peak, ZHR, radiant). Comets from cached MPC elements, propagated locally for RA/Dec/magnitude. ISS passes from cached GP elements via SGP4, filtered to visible passes (sunlit satellite, observer in darkness, max elevation ≥ 30°). Eclipses and conjunctions from Ephemeris. | Ephemeris, Fetcher |
| `Planner` | For a site and a night: darkness interval; clear windows (contiguous hours meeting the go rule); score 0–100; target ranking for the best window; tonight and tomorrow summaries. | Forecast, Ephemeris, Catalog, Events |
| `Alerts` | Pure state machine per night. Input: now, plan, previous state, settings. Output: zero or one `Notification` and the new state. | Planner |
| `Settings` | Codable config struct with defaults, JSON load/save. | none |

SGP4: use an existing MIT Swift SGP4 package if one is verified during planning; otherwise vendor the public-domain Vallado C reference as a second C target. Decision recorded in the implementation plan.

### 4.2 `Nightwatch` (app)

SwiftUI, `MenuBarExtra` with `.window` style, `LSUIElement` true. No Dock icon, no main window on launch.

| Component | Responsibility |
|---|---|
| `Scheduler` | `NSBackgroundActivityScheduler`, interval 30 min, tolerance 10 min. Also runs on wake from sleep and when the popover opens if the cache is older than 30 min. |
| `Location` | On launch, if authorised, one `CLLocationManager` fix. Manual site selected in settings always wins. Falls back to last known site. |
| `Store` | Reads and writes `config.json` and cache files. Owns the current `Plan`. Publishes to views. |
| `Thumbnails` | Builds hips2fits URL for object centre at the user's FOV (or the object's size × 1.5 when the object exceeds the FOV), fetches on first view, writes JPEG to cache, never refetches unless FOV changes. |
| `Notifier` | Requests authorisation once. Posts `UNNotificationRequest` for each `Notification` the state machine emits. |
| `MenuIcon` | Template image with four states: none, later, go, stale. |
| Views | Popover (Tonight), Targets window, Detail window, Settings window, About window. |
| Login item | `SMAppService.mainApp.register()` on first run after user consent in settings. Verified in the plan step; fallback is a LaunchAgent plist written by `build-app.sh`. |

### 4.3 Storage

- `~/Library/Application Support/Nightwatch/config.json` — settings (below). Symlink into iCloud Drive or a synced folder to share across Macs. The app follows symlinks and reloads on change.
- `~/Library/Caches/Nightwatch/` — `forecast.json`, `plan.json`, `comets.json`, `iss-gp.json`, `thumbs/<objectId>-<fovKey>.jpg`, `alerts-state.json`. Each JSON carries `fetchedAt`.

Config fields: `sites[] {name, lat, lon, elevationM, timeZone, bortle}`, `activeSite` or `"auto"`, `fov {presetId, widthDeg, heightDeg}`, `goRule {minHours, maxCloudPct, minAltitudeDeg}`, `alerts {headsUp, tomorrowPreview, preWindowMinutes, cancelOnDowngrade, quietHours {start, end}}`, `flavour: "watch" | "plain"`, `loginItem`.

### 4.4 Data flow

```
Scheduler tick
  → Forecast.fetch (skip if cache < 30 min)
  → Ephemeris night bounds for tonight and tomorrow at active site
  → Planner.windows → Planner.score → Planner.rankTargets
  → Alerts.step(now, plan, state) → maybe Notification
  → Store.save(plan, state) → MenuIcon.update → Notifier.post
```

The popover always renders from `Store.plan`. It never waits on network.

### 4.5 Planner rules

- Darkness: astronomical twilight end to astronomical twilight start. If none (high latitude summer), the plan reports "no astronomical darkness" and no alerts fire.
- Clear window: maximal run of consecutive forecast hours within darkness where total cloud ≤ `maxCloudPct`. Windows shorter than `minHours` are discarded. Multiple windows allowed; the longest is primary.
- Score 0–100: 60 % from clear fraction of darkness weighted by window contiguity, 15 % Moon (illumination × above-horizon fraction inverted), 15 % seeing and transparency when present (else redistributed to cloud), 10 % wind and dew spread penalties.
- Target eligibility: altitude ≥ `minAltitudeDeg` (default 30°) for at least half the primary window; Moon separation ≥ 30° or flagged "Moon-washed"; magnitude ≤ 12 for deep sky.
- Fits frame: < 5′ → "small"; major axis ≤ max(FOV width, FOV height) → "fits" (an elongated object is framed along the longer side); otherwise "mosaic". Amended 2026-09-23 during implementation: the original min() rule contradicted the NGC 7000 expectation.
- Ranking: eligible targets sorted by (fits frame, peak altitude in window, brightness), one list per group. "Best tonight" is the top three across groups with at most one per group.
- Suggested stack length: min(window length, 3 h), shown as guidance only.

### 4.6 Alert state machine

Night key = local calendar date of that night's sunset at the active site.

States per night: `idle → headsUpSent → goSent → done`, with `cancelled` reachable from `headsUpSent` or `goSent`.

- Heads-up: fires once when now ≥ sunset − 60 min and the night qualifies. Includes window, score, best target names. If tonight fails and tomorrow qualifies, the same slot sends a tomorrow preview instead.
- Go nudge: fires once when now ≥ window start − `preWindowMinutes` and the night still qualifies.
- Cancel: fires once if a night that had a heads-up or go alert no longer qualifies.
- Quiet hours: a notification due inside quiet hours is dropped, not deferred, and the popover shows what was missed.
- Stale guard: no notification when forecast `fetchedAt` is older than 6 h.

### 4.7 Failure handling

- Offline: keep last plan; icon shows stale after 6 h; popover shows "last updated" time.
- HTTP error or timeout: exponential backoff 5, 10, 20 … minutes, capped at 2 h, then normal cadence.
- 7Timer missing or errored: seeing and transparency show "n/a", score redistributes their weight.
- hips2fits failure: card shows the group's placeholder glyph; retried on next view.
- Catalogue parse error at launch: app shows an error in the popover and continues with an empty catalogue rather than crashing.

### 4.8 Build and portability

- `swift build -c release`
- `scripts/build-app.sh`: assembles `Nightwatch.app/Contents/{MacOS,Resources,Info.plist}`, sets `CFBundleIdentifier`, `LSUIElement`, `NSLocationUsageDescription`, copies bundled data, ad-hoc `codesign -s -`, copies to `/Applications`, launches.
- Locally built apps carry no quarantine attribute, so Gatekeeper does not prompt.
- Same command on every Mac. Requires macOS 14+ and Command Line Tools.

### 4.9 Testing

`SkyCoreTests` with fixtures under `Tests/Fixtures/`:

- Forecast: parse Open-Meteo and 7Timer samples; merge alignment across 3 h steps; missing fields.
- Ephemeris: spot checks against JPL Horizons values for sunrise, sunset, astronomical twilight, Moon illumination and a planet's alt/az, at Sheffield and Sydney on the same dates, tolerance 2 min and 0.5°.
- Planner: no window, one window, window crossing midnight, two windows, no darkness, Moon-washed flag, fits/mosaic/small thresholds.
- Alerts: full transition table including quiet hours drop, cancel after go, tomorrow preview, stale guard, idempotence on repeated ticks.
- Catalog: row count, type mapping, addendum merge, Messier cross-reference.
- Events: shower active-range lookup, one comet element propagation against a Horizons value, one ISS pass against a CelesTrak-published pass (tolerance 1 min).

App layer: launch smoke test in `build-app.sh` (process starts, menu item present).

## 5. UI

Dark by default, follows system appearance otherwise. System font. Accent red `#ff453a` on `#14171e` surfaces (owner decision 2026-09-23: red preserves dark adaptation at the telescope; the earlier green accent is retired). Secondary badge colour `#8fb4ff`. Mockups: owner-approved, 23 September 2026.

1. Popover "Tonight": site and date, score ring, verdict line, clear window, cloud strip for the night, six tiles (dark, Moon, seeing, wind, dew risk, transparency), best three targets, notify toggle, updated time.
2. Targets window: sidebar of groups with counts and glyphs; grid of cards (thumbnail, name, magnitude, altitude bar, best time, badge); filters (fits FOV, above 30°, include Moon-washed); search.
3. Detail window: thumbnail with dashed FOV overlay, facts, four tiles, altitude curve with window shaded, RA/Dec, external link.
4. Settings window: sites, FOV preset, go rule, alerts, quiet hours, flavour, login item, attribution.
5. Menu icon states and notification copy as in the Notify artboard.

## 6. Discworld flavour

Nightwatch takes its name from the City Watch. Owner's brief: subtle, in key with a quiet astronomy tool, there if the reader gets it and invisible if they do not. Rules: naming and short copy only; every flavoured string must also read as ordinary English; no quoted passages beyond a few words; no official artwork; no character names in the UI. All flavoured strings live in one strings table; `flavour: "plain"` swaps in literal wording. Defaults:

| Concept | Watch flavour | Plain |
|---|---|---|
| Background refresh (menu item, logs) | Patrol | Refresh |
| Saved site | Beat | Site |
| Dark-site card button (v0.6.4: the owner ruled that "Use as beat" lost people, so this action is plain in both modes) | Observe from here | Observe from here |
| Go alert title | All's well. Clear from 22:40 | Clear from 22:40 |
| Cancel alert title | Stand down. Clouds moving in | Cancelled. Clouds moving in |
| Less-certain alert title (v0.6.3: the two forecasts split after a heads-up or nudge) | Hold fire. Forecasts disagree | Less certain. Forecasts disagree |
| No-window empty state | Nothing to see here. Move along. | No clear window tonight. |
| Stale / offline | Off the beat since 19:32 | Offline since 19:32 |
| About window | A small original turtle glyph beneath the credits, unlabelled | Credits only |
| Release names (git tags and changelog only) | 0.1 Guards! Guards! · 0.2 Men at Arms · 0.3 Feet of Clay · 0.4 Jingo · 0.5 The Fifth Elephant · 1.0 Night Watch | Semver only |

Everything else uses plain wording in both modes: Settings, Refresh, Best tonight, score bands Excellent / Fair / Poor / Overcast, Frost likely.

## 7. Repository layout

```
nightwatch/
  Package.swift
  Sources/
    CAstronomyEngine/      vendored C source + module map
    SkyCore/               Forecast, Ephemeris, Catalog, Events, Planner, Alerts, Settings
    Nightwatch/            App, Scheduler, Location, Store, Thumbnails, Notifier, Views, Strings
  Resources/
    catalog/OpenNGC.csv, addendum.csv, constellations.json
    events/meteor-showers.json
    presets/telescopes.json
  Tests/
    SkyCoreTests/
    Fixtures/
  scripts/build-app.sh
  docs/specs/, docs/plans/
  LICENSE (MIT), NOTICE (data attributions), README.md
```

## 8. Out of scope for v1

WidgetKit widget (Xcode required), light-pollution raster, telescope control or any DwarfLab protocol, image stacking, iOS, cloud sync beyond a synced config file, Caldwell catalogue, user accounts, analytics.
