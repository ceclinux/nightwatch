# One listing pass: iPhone/iPad 1.0.3 and Mac 1.7.4 (7 November 2026)

Owner, 7 November: optimise the App Store listing completely in one go rather than by repeated tweaks. Approved: the keyword sets below, the accessibility
audit, the iPhone and iPad preview videos, and bundling every change into one release. This file is the plan; the checked listing text is in
`docs/plans/release-1.0.3/` (`listing-ios.json`, `listing-mac.json`, `claims-ledger.json`, `rank-log.json`). Nothing here has been entered in App Store Connect.

## Why one release, and the honest cost

App Store Connect says name, subtitle, category, keywords, description and screenshots "release with your next app version"; only promotional text, custom product
pages, in-app events and the accessibility labels can change without one. The optimiser skill's own rule is **one search-metadata change per release** so a
result can be attributed. Bundling gives that up (the owner chose it), so the baseline below is recorded first and a before-and-after read is taken two to four
weeks after release with `rank_log.py` and App Analytics (source: App Store Search).

The code had not changed since 1.0.2 and 1.7.3 until 7 November, when the local test run found that macOS 27.0.1 names London's winter zone "GMT+0", so the widget
would say "UTC+0" beside a window read on a US clock. `Copy.zoneName` now returns "GMT" for a zero offset; that is the one real change in 1.0.3 and 1.7.4, and the
What's New line says it. Decision on the eight stars, 7 November: **not shipped** (eight of about two thousand targets; a survey cutout of a bright star is a saturated blob;
it would need a rebuilt pack, a new release asset and app code, in a release meant to be the last listing pass). Revisit in any later release.

## Baseline (recorded before any change)

Positions from Apple's public search API, UK, iPhone software, 7 November 2026. **This is not the real App Store ordering** (the skill tested it on 5 November
and it missed the Mac app), so treat it as a rough marker only. The owner declined to let the App Store app be driven for a hand-read baseline.

| Term | Position | Term | Position |
|---|---|---|---|
| nightwatch: clear sky alerts | **#1** | cloud cover | not in top 156 |
| nightwatch | **#4** | stargazing | not in top 169 |
| seeing | #60 of 114 | astronomy | not in top 179 |
| astrophotography | not in top 161 | telescope | not in top 169 |
| astronomy forecast | not in top 154 | stars | not in top 173 |
| smart telescope | not in top 170 | dark | not in top 159 |
| light pollution | not in top 176 | moon | not in top 186 |

Hand-check list for the owner (about ten minutes, Mac App Store search, Mac Apps tab and iPhone & iPad Apps tab, UK storefront): `nightwatch`, `astrophotography`,
`astronomy forecast`, `smart telescope`, `light pollution`, `stargazing`, `seeing`. Record each with `python3 scripts/rank_log.py add ...` from the skill, source
`app-store`. Repeat two and four weeks after release.

## The changes

### Keywords (the only search-metadata change besides screenshots and the description)

Checked with `listing_check.py --strict`: 0 failures, 0 warnings.

| | Keywords | Bytes |
|---|---|---|
| iPhone and iPad now | `astronomy,telescope,stars,forecast,seeing,dark,aurora,moon,nebula,galaxy,messier,stargazing,bortle` | 98 |
| iPhone and iPad proposed | `astronomy,telescope,forecast,stargazing,aurora,nebula,galaxy,messier,bortle,smart,light pollution` | 97 |
| Mac now | `astronomy,telescope,stars,forecast,seeing,dark,aurora,moon,nebula,galaxy,messier,bortle,menu bar` | 96 |
| Mac proposed | `astronomy,telescope,forecast,aurora,nebula,galaxy,messier,bortle,smart,light pollution,menu bar` | 95 |

Out: `stars`, `seeing`, `dark`, `moon` (generic or ambiguous; "seeing" is the only one with any showing, #60 of 114 on the proxy, where "Seeing AI" leads).
In: `smart` (with `telescope`: "smart telescope" is a low-competition phrase) and `light pollution` (a medium-competition phrase the app genuinely serves).
Competition bands from `keyword_plan.py` (7 November): low: astrophotography, astronomy forecast, smart telescope, cloud cover, bortle, observing; medium: light
pollution, deep sky; high: moon phase, night sky, stargazing, astronomy, aurora. Bands are rivals, not search volume; Apple publishes no ranking weights.
Alternates if `galaxy` and `messier` are dropped: `cloud cover`, `observing` (both low).

**Name, subtitle and categories stay.** Name "Nightwatch: Clear Sky Alerts" (28 of 30), subtitle "Astrophotography night planner" (30 of 30; "astrophotography" is a
low-competition term), categories Weather and Utilities. No evidence supports a change.

### Descriptions

- iPhone and iPad: three bullets added (presets for popular smart telescopes, a colour sky-survey picture of each of 1,948 targets downloaded once (about 18 MB),
  the next run of moonless nights). The "best" wording is not in this text. 1,588 of 4,000 characters.
- Mac: the same three bullets; "the best targets" becomes "the targets that suit" (the checker's Guideline 2.3.7 warning on "best"); "Nightwatch only suggests what clears
  them" becomes "picks targets that clear them" (the planner ranks by clearance and gives targets behind the horizon a reason; "only" overstated it); "in the order of
  their best time" becomes "in the order they peak". 1,626 of 4,000 characters.
- Not added: the rain-after-the-window warning, which is on the Mac only (`Copy.rain` is used in `TonightView.swift`, not in the phone code).
- Claims ledger: C3 removed (the greyscale second source went in 1.0.2 and 1.7.3); C8 to C10 added for the new bullets. `check_claims.py`: 0 failures on both.

### What's New (both platforms)

"A time zone is named correctly beside a window: GMT, not UTC+0, when a GMT site is read on another clock. Refreshed screenshots and App Store text."

### Screenshots and previews (files in `~/Downloads/Nightwatch-1.0.3-store-assets/`)

| | What | Size | Check |
|---|---|---|---|
| iPhone | 9 framed screenshots, captioned, 6.3-inch class (the medium-display tab) | 1206 x 2622 | `asset_check.py`: 0 failures, 0 warnings |
| iPad | 5 framed screenshots, 13-inch | 2064 x 2752 | same |
| Mac | 6 framed screenshots | 2880 x 1800 | same |
| iPhone preview | 19.8 s: Tonight, a target page with How to shoot, the plan, the week, dark sites. Silent, demo mode, Malham Tarn | 886 x 1920, H.264 | 0 failures, 0 warnings |
| iPad preview | 16.3 s: Tonight, the plan, the week | 1200 x 1600, H.264 | 0 failures, 1 warning (bit rate 3.9 Mbps against Apple's 10 to 12 target; mostly still content; guidance, not a limit) |
| Mac preview | not made | 1920 x 1080 | the owner records the screen (QuickTime), then `encode_preview.py rec.mov out.mp4 --target mac` |

Captions are 10 words or fewer, no price, no URL, no Apple recognition. The how-to-shoot shot names DWARFLAB's manual; the owner confirmed that is fine.
All captures use public sites (Malham Tarn on the phone, Furnace Creek on the Mac); none shows home. Re-shoot the Mac set and the previews if a later change alters the look.
Set each preview's poster frame deliberately (Apple's default is at 5 s); for the iPhone, the Tonight hero at about 1.5 s.

### Accessibility labels

See `docs/plans/2026-11-07-accessibility-audit.md`. Not tied to the version; do it once the tests are done.

### After approval (the second half of the pass)

- Custom product pages: assign keywords from the **approved** version, each combination to one page only. Suggestion: "Smart telescope owners": `smart`, `telescope`;
  "Blocked horizon": `light pollution`, `bortle`. Page B's new draft (without `stars`) is waiting for the owner to press Add for Review.
- Promotional text can change any time without review (not searched): once the Moonless week event is live (promotion from 22 November, event 5 to 13 December), add the hook.
- The Mac DMG: no GitHub release for 1.7.4 unless the code changes (an identical DMG adds nothing).

## Steps and owners

1. (me) Version bump commit: `Sources/Nightwatch/Info.plist` 1.7.3 (56) to 1.7.4 (57), `project.yml` the same; `Phone/project.yml` 1.0.2 (11) to 1.0.3 (12) in its three places. Build with `scripts/appstore.sh` and `Phone/scripts/appstore.sh`; inspect both packages independently.
2. (owner) Upload both builds with Transporter and press Deliver, as before.
3. (me, in the owner's signed-in Chrome, with their word for each window) Create the 1.0.3 and 1.7.4 versions; paste the keywords, description, What's New; set Version Release; upload the screenshots and previews to the version page; select the build; **stop before submitting**.
4. (owner) Press Add for Review, or say so and I do (the owner has pressed it every time so far).
5. (me) After approval: confirm both versions READY_FOR_DISTRIBUTION with `scripts/review-status.swift` and the public lookup; assign the custom pages' keywords; re-test the two custom links.
6. (both) Record positions two and four weeks later; compare with the baseline; add a lesson to the skill if the result is clear.

## Timing

To be live before the Moonless week event is promoted (22 November) and the nomination window opens (1 December): decide the picture-set stars question about 14 November,
build about 16 November, submit about 17 November, approval about 19 to 20 November.

## Open decisions

- The stars in the picture set (about 14 November, depends on whether CDS is back).
- Whether the Mac preview is worth a screen recording.
- Whether to raise the Dynamic Type caps if the Larger Text test fails (a small code change; it would move the accessibility label and the What's New).
