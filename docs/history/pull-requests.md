# Pull request and discussion history

The descriptions of every pull request and discussion from the repository's first home on GitHub, kept here when the
repository was recreated on 25 September 2026 to remove the owner's home location from its history. The code, commits
and tags are unchanged apart from that; the pull-request pages themselves did not survive the move.

## Discussion 1: What should Nightwatch 0.3 do? Six questions for UK observers

*Ideas · rsutcliffe · 2026-09-24*

Nightwatch is a silent macOS menu-bar app that tells you when tonight is clear enough for a long imaging session, and what to point at. Version 0.2.0 shipped this week with dark-sky sites. Before deciding what goes into 0.3, I would like to hear from people who actually observe or image in the UK, whether or not you use the app. The README describes what it does today.

Six short questions. Reply with the numbers you care about; partial answers are welcome.

1. **Which forecast do you trust for clear nights?** Clear Outside, Met Office, Apple Weather, Meteoblue, Windy, Astrospheric, something else? And do you cross-check more than one before going out?

2. **Which of these alert or event services do you use now?** BAA alerts by email, AuroraWatch UK, comet or nova alerts (COBS, AAVSO), occultation predictions (IOTA, OccultWatcher), Starlink pass sites, none. Would one combined notifier on your Mac replace any of them?

3. **Which device do you check before deciding to go out?** Phone, Mac, tablet, a look out of the window. Would a Mac notification reach you in time, or does it need to be on your phone?

4. **Summer.** From mid-May to the end of July there is no astronomical darkness in Sheffield, and the default rule (3 contiguous dark hours, cloud at or under 25 percent) never fires for about 14 weeks. Would Moon and planet suggestions on bright nights be useful to you, or is the quiet correct?

5. **Dark sites.** How many times in the past year did you drive somewhere darker to image? Would a one-line "tonight is better at X, 40 km away" verdict have changed any of those decisions?

6. **Records.** Do you keep any log of what you imaged? If the app kept one automatically per alert (window, target, outcome), would you use it, or is that noise?

One more, if you have an opinion: does an MIT licence and a build-from-source Swift package matter to you as a user or a contributor, or is "free and it works" the whole story?

Thanks. Answers here shape 0.3 directly.

## #2: docs: v0.3 Feet of Clay design spec

*merged 2026-09-24 · `docs/v0.3-spec` → `main`*

Design spec for v0.3 "Feet of Clay", approved in conversation on 24 September 2026.

Scope: bright-night mode (Moon and planets when the dark rule cannot be met, opt-in), completion of the best-spot path (popover line lands on the dark-site card; cards compare score and darkness against home), and two v0.2 housekeeping items. Everything else from the product-direction discovery is held for discussion #1 or closed by owner rulings, as the spec records.

No-issue: design document, no tracking issue for the spec itself.

## UAT

**UAT:** Open `docs/specs/2026-09-24-v0.3-feet-of-clay-design.md` → read sections 1, 3 and 4 → the success criteria match what was agreed (bright nights opt-in, Moon and planets only, no new copy, best-spot completion, PRs per task); nothing under "Out of scope" is something you expected in 0.3.

## #3: docs: v0.3 Feet of Clay implementation plan

*merged 2026-09-24 · `docs/v0.3-plan` → `main`*

Implementation plan for the v0.3 spec merged in #2. Eight serial tasks, each its own PR: nautical twilight, BrightSettings, the bright plan in Planner, bright alert copy, the popover/targets/settings views, best-spot completion, site-cache pruning, docs and version 0.3.0.

No-issue: planning document, tracked by the spec.

## UAT

**UAT:** Open `docs/plans/2026-09-24-v0.3-feet-of-clay.md` → skim the Global Constraints and the eight task headings → they match the spec's delivery order and every task ends in a PR with a UAT line.

## #4: feat(skycore): nautical twilight on Night

*merged 2026-09-24 · `feat/v0.3-t1-nautical-twilight` → `main`*

Task 1 of the v0.3 plan. `Night` gains `nauticalStart` / `nauticalEnd` (Sun at −12°) and `hasNauticalDarkness`, computed through one shared crossings helper that the −18° darkness now uses too.

Also fixes a latent bug found while testing: the search for the Sun climbing back through the threshold started at the exact instant it went down, and on nights where the Sun barely dips below the threshold it returned that same instant. In northern England on the June solstice that gave a zero-length nautical night instead of about 1.5 h. The −18° darkness code had the same pattern, so its short nights in mid-May and early August were exposed to it too. The return search now starts one minute after the crossing.

Checked at Home after the fix (dark / nautical hours): 28 Apr 3.55 / 5.90, 10 May 0.97 / 4.76, 14 May none / 4.38, 20 Jun none / 1.56, 5 Aug 2.16 / 5.15, 24 Sep 7.95 / 9.39. 108 tests pass; release build clean; task review approved.

No-issue: v0.3 plan task, tracked by docs/plans/2026-09-24-v0.3-feet-of-clay.md.

## UAT

**UAT:** Run `scripts/test.sh` → 108 pass, including `nauticalTwilightExistsAtTheTestSiteInJuneWhenAstronomicalDoesNot` (1 to 2 h of nautical darkness on 20 June) and `noNauticalTwilightInPolarDay`.

## #5: feat(skycore): BrightSettings on Config; 1 h bright minimum

*merged 2026-09-24 · `feat/v0.3-t2-bright-settings` → `main`*

Task 2 of the v0.3 plan. `Config.brightNights` holds the bright-night mode setting: off by default, minimum clear run 1 h, clamped to 1 to 6 h on decode, and decoded leniently so older config files keep working.

The same commit amends the v0.3 spec and plan from a 2 h to a 1 h default, per your ruling today: nautical darkness in northern England lasts only about 1.5 h at the June solstice, so 2 h would have silenced the mode in the weeks it exists for. Scotland gets no nautical darkness for about four weeks around midsummer, which you accepted.

109 tests pass; release build clean; task review approved with no findings.

No-issue: v0.3 plan task, tracked by docs/plans/2026-09-24-v0.3-feet-of-clay.md.

## UAT

**UAT:** Run `scripts/test.sh` → 109 pass, including `brightSettingsDefaultAndLenientDecode`; in the PR's Files tab, the spec and plan say 1 h for the bright minimum and nowhere still say 2 h.

## #6: feat(skycore): bright-night plan with a 15° target floor

*merged 2026-09-24 · `feat/v0.3-t3-bright-plan` → `main`*

Task 3 of the v0.3 plan. With bright-night mode on, a night with too little astronomical darkness for the dark rule gets a bright plan instead: clear hours between nautical dusk and dawn in which the Moon (10 % lit or more) or a naked-eye planet stands at 15° or higher, for at least the minimum run (1 h by default). Deep-sky targets are never suggested on a bright night, and the Moon no longer lowers the score because it is the target. The no-window reason now names nautical darkness and the bright rule, and says so when nothing was up.

Amends the spec and plan per your ruling today: 30° at the window midpoint would have produced no window on any of the 94 summer nights at Home in 2026. 15° for an hour gives about 39 of them before cloud.

Bright mode off, or any night where the dark rule can be met, returns exactly the 0.2.2 result. 116 tests pass (7 new); release build clean; task review found the code correct and two stale spec sentences plus one loose test, all fixed in the second commit.

No-issue: v0.3 plan task, tracked by docs/plans/2026-09-24-v0.3-feet-of-clay.md.

## UAT

**UAT:** Run `scripts/test.sh` → 116 pass, including `brightPlanOnAJulyNightWithTheMoonUp` (30 July: Moon first in the bright targets), `brightPlanNeedsATargetUp` (15 June: no window) and `darkPlanWinsWhenTheDarkRuleIsMet` (24 September unchanged).

## #7: feat(skycore): bright-night alert wording

*merged 2026-09-24 · `feat/v0.3-t4-bright-alerts` → `main`*

Task 4 of the v0.3 plan. On a bright plan the notifications read:

- heads-up: "Bright night tonight from 22:30 · Moon 62%, Saturn"
- go: "Bright night. Clear from 22:30"
- tomorrow preview: "Tomorrow looks bright and clear · 2.5 h"
- body: "Moon 62%, Saturn well placed."

The same words in both wording modes, with no new Discworld lines, as you ruled. Dark-night notifications and the stand-down are unchanged. 118 tests pass (2 new); release build clean; task review approved with no findings.

No-issue: v0.3 plan task, tracked by docs/plans/2026-09-24-v0.3-feet-of-clay.md.

## UAT

**UAT:** Run `scripts/test.sh` → 118 pass, including `brightHeadsUpGoAndPreviewUseBrightWording`, which checks the heads-up, go and preview titles and the body string above.

## #8: feat(app): bright-night verdict, targets and settings

*merged 2026-09-24 · `feat/v0.3-t5-bright-views` → `main`*

Task 5 of the v0.3 plan: the first bright-night change you can see in the app.

- **Settings › Bright nights:** a toggle, "Moon and planets when there is no proper darkness" (off by default), and the minimum clear run (1 to 6 h, default 1 h), with a caption explaining when it applies.
- **Popover on a bright night:** "Bright night: Moon and planets", the window, and the targets ("Moon 62%, Saturn"); the date line gains "· bright night"; the Best row shows the Moon and planets. With no window, the reason line names nautical darkness, or says no Moon or planet was 15° up.
- **Targets window:** the Planets group lists the Moon and planets; the other groups note that no deep-sky targets are suggested on a bright night.
- **Dark sites:** site plans use the same setting, so cards compare like with like.

Live-checked on the installed app. I temporarily set your config to bright nights on with a 10-hour dark rule, which forces tonight into bright mode, then restored it. The app wrote a bright plan for tonight: 00:00 to 05:00 BST, with the Moon, Saturn, Mars and Jupiter and no deep-sky targets. After restoring your config it went back to the normal dark plan. With bright nights off, every view is unchanged from 0.2.2.

The review found one gap, now fixed in the second commit: a bright plan at a site with no nautical darkness (Scotland near midsummer) showed a bare no-window line; it now gets the "No astronomical darkness" verdict as the spec requires. 118 tests pass; release build clean.

No-issue: v0.3 plan task, tracked by docs/plans/2026-09-24-v0.3-feet-of-clay.md.

## UAT

**UAT:** Settings › Bright nights → the toggle is off and the minimum run reads 1.0 h; turn it on → tonight's popover is unchanged in late September (the dark rule is met), which is correct. To see a bright night now, set Go rule › minimum hours above tonight's darkness (e.g. 10) → the popover says "Bright night: Moon and planets" with the Moon and planets listed; set it back afterwards.

## #9: feat(app): Clearer sky line lands on the dark-site card; cards compare with home

*merged 2026-09-24 · `feat/v0.3-t6-best-spot` → `main`*

Task 6 of the v0.3 plan.

- The popover's "Clearer sky" line now names the site's darkness band ("… Yorkshire Dales (Dark), clear 00:00–04:57 →") and, when clicked, opens the Targets window on **Dark sites** with that site's card scrolled to the top. This works whether or not the Targets window was already open.
- Every dark-site card gains one line comparing it with home: "Score 61 vs 37 at home · Dark, home Bortle 5", shown in the accent colour when the site beats home by the same 20-point margin the popover line uses; cards without a forecast show "Dark, home Bortle 5".

118 tests pass; release build clean; task review approved with no findings on all six named risks (window already open, scroll timing, card ids, macOS 14 onChange, no @State, colour-rule parity). The landing and scroll were checked by review, not by clicking, since I can't drive the popover from here.

No-issue: v0.3 plan task, tracked by docs/plans/2026-09-24-v0.3-feet-of-clay.md.

## UAT

**UAT:** Targets › Dark sites → each card shows "Score N vs M at home · <band>, home Bortle 5". On a night when a site beats home by 20, click the popover's "Clearer sky …" line → Targets opens on Dark sites with that card at the top (also try it with the Targets window already open).

## #10: feat(app): prune the site forecast cache to current sites and 24 h

*merged 2026-09-24 · `feat/v0.3-t7-cache-pruning` → `main`*

Task 7 of the v0.3 plan. After each dark-sites recompute, the per-site forecast cache keeps only files for sites in the current list and nothing older than a day. Any error is ignored, since the cache is disposable, and a superseded recompute never prunes against an old list.

Checked on your Mac: the cache went from 16 files to 9 after one recompute. The seven removed were Sheffield-era spot files and sites no longer in the Home list; the eight current sites and one current site's file under a day old stayed.

120 tests pass (2 new: the selection rule, and a real temporary folder including a missing one); release build clean; task review approved with no findings.

No-issue: v0.3 plan task, tracked by docs/plans/2026-09-24-v0.3-feet-of-clay.md.

## UAT

**UAT:** After a Patrol, `ls ~/Library/Caches/Nightwatch/sites` → only files named after sites listed in Targets › Dark sites, none older than a day.

## #11: docs: v0.3 adds aurora alerts (spec §4.6, plan Task 8)

*merged 2026-09-24 · `docs/v0.3-aurora` → `main`*

Adds aurora alerts to v0.3, per your decision today: free or open data only.

- **Source:** AuroraWatch UK's current status (Lancaster University), `https://aurorawatch-api.lancs.ac.uk/0.2/status/current-status.xml`, checked live (it returned `green`). Free with no key; terms are non-commercial use, attribution, correct colour and name, polls no more than every 3 minutes. NOAA's Kp forecast is also free JSON, but its licence for those feeds isn't stated on the pages I read, so it stays out.
- **Rule:** notify when the status is at or above your threshold (default amber), the Sun is at least 12° down, and the current forecast hour is under your cloud limit; once per level per night, again if it rises; quiet hours apply. Off by default.
- **Where it shows:** a notification ("Aurora alert: amber · clear at Test site now"), a popover line while the status is up, a Settings section with the threshold, and the AuroraWatch UK acknowledgement in About and NOTICE.
- **Plan:** aurora becomes Task 8; docs and the 0.3.0 bump move to Task 9 and include aurora (UAT item 18).

No-issue: design amendment, tracked by the v0.3 spec and plan.

## UAT

**UAT:** Read spec §4.6 and plan Task 8 → the source, rule, polling and wording match what you want; note anything to change (e.g. a different default threshold, or aurora ignoring quiet hours) before merging.

## #12: feat(app): aurora alerts from AuroraWatch UK, gated on local cloud

*merged 2026-09-24 · `feat/v0.3-t8-aurora` → `main`*

Task 8 of the v0.3 plan (spec §4.6).

- **Settings › Aurora:** "Alert me to aurora when the sky is clear" (off by default) and "Alert from" Yellow / Amber / Red (default Amber), with a caption naming AuroraWatch UK and the rule.
- **Polling:** only while enabled and the Sun is at least 12° down: every 5 minutes, and never twice within 3 minutes whatever triggers it (boot, timer, wake), per AuroraWatch UK's terms.
- **Alert:** when the level reaches your threshold and this hour's forecast cloud is under your limit: "Aurora alert: amber · clear at Test site now" / "AuroraWatch UK reports amber. Cloud 10% this hour." Once per level per night, again if it rises; quiet hours apply.
- **Popover:** "Aurora: amber (AuroraWatch UK)" while the level is at or above your threshold.
- **Credit:** About, NOTICE and the Settings caption name AuroraWatch UK (Lancaster University), used under its non-commercial terms.

Live-checked on the installed app with aurora temporarily switched on in your config (then restored): after dark it fetched AuroraWatch UK's status, green at 20:39:31Z, matching a direct query, recorded tonight's alert state and posted nothing, since green is below amber.

Review found two issues, one fixed and one ruled against on live evidence: the missing 3-minute guard (fixed), and a claim that AuroraWatch's update time only changes with the level (disproved: it moved from 20:33:32 to 20:39:31 while green, so hiding the line on a stalled feed is right). 123 tests pass (3 new); release build clean.

**One question for you:** AuroraWatch UK asks that the status be shown "with its correct colour and name". The name is shown verbatim; the colour uses Nightwatch's night-safe palette (yellow in amber-orange, amber and red in the red accent, never green) rather than their traffic-light colours. If you read their terms as requiring their own colours, say so and I'll change it.

No-issue: v0.3 plan task, tracked by docs/plans/2026-09-24-v0.3-feet-of-clay.md.

## UAT

**UAT:** Settings › Aurora → toggle on, Alert from Amber → the caption names AuroraWatch UK; after dark, `cat ~/Library/Caches/Nightwatch/aurora.json` shows the current level within 5 minutes; when AuroraWatch UK next reports amber or red on a clear night outside quiet hours, the notification arrives and the popover shows the status line.

## #13: docs: v0.3.0 README, overview, UAT and version

*merged 2026-09-24 · `feat/v0.3-t9-docs-version` → `main`*

Task 9, the last v0.3 task.

- **README:** bright nights and aurora bullets under "What it does"; the dark-site cards' home comparison, the Clearer sky landing and cache pruning under "Dark-sky sites".
- **Product overview:** version 0.3.0 "Feet of Clay", bright nights in "How it decides", aurora in Alerts and Data sources, Settings list, 123 tests, and the 0.3.0 release row.
- **UAT:** items 13 to 18 (bright nights on and off, the dark rule still winning in September, the Clearer sky landing, cache pruning, aurora).
- **Version:** 0.3.0 (build 5). The installed app reports 0.3.0; 123 tests pass.

After you merge, I tag v0.3.0 "Feet of Clay" on the merge commit.

No-issue: v0.3 plan task, tracked by docs/plans/2026-09-24-v0.3-feet-of-clay.md.

## UAT

**UAT:** About window → "Version 0.3.0"; `docs/uat.md` ends with items 13 to 18; the README lists Bright nights and Aurora under "What it does".

## #14: docs: v0.4 Jingo, Liquid Glass redesign spec

*merged 2026-09-24 · `docs/v0.4-spec` → `main`*

Spec for v0.4 "Jingo", taking your Liquid Glass design handover as the visual target, with your rulings applied: the app's red (#ff453a) stays, the EQ tilt stays in the header, the name stays Nightwatch, and Patrol stays Patrol.

Also settled in the spec: stale forecast = the existing six hours; darkness over 12 hours shows the 12 hours around the clear window; the "SKY SCORE" caption goes to 9 pt as the handover's accessibility section recommends; the popover height grows with content rather than fixed at 567 pt so v0.3's extra lines never clip.

Three assistant rulings you can overrule while reviewing (section 2): the dew hint reads "Dew heater advised" rather than "Heater on" (the app can't know if a heater is running); the v0.3 lines the mock-ups predate (aurora, Clearer sky) share one notice row under the bars; the warning amber adopts the handover's #F5B041.

Platform check: `glassEffect`, `GlassEffectContainer` and `Glass` are in the Command Line Tools SDK, available from macOS 26, so the redesign builds without Xcode, with a solid-fill fallback on macOS 14 and 15 and under Reduce Transparency.

No-issue: design document; the plan follows once this is merged.

## UAT

**UAT:** Read sections 2 and 5 → the decisions match your rulings and the three assistant rulings are acceptable (comment on this PR if not), and nothing in section 10 is something you expected in 0.4.

## #15: fix: v0.3.1, fixes from the v0.3.0 release review

*merged 2026-09-24 · `fix/v0.3.1-review` → `main`*

The final whole-release review found v0.3.0 sound, with fixes worth making. All are here; a scoped re-review confirmed each is addressed with no new breakage.

**Important**
- **Aurora:** a status that AuroraWatch UK published over an hour ago never alerts. Before, a storm status cached at dawn could fire "Aurora alert … clear at Test site now" the next evening if the Mac woke before Wi-Fi.
- **Bright nights:** the no-window reason now measures the run exactly as the rule does (clipped to nautical darkness, target 15° up) and prints half-hour minimums correctly. At the solstice it now says "No Moon or planet 15° up in the clear hours of nautical darkness." instead of "run is 1 h; the rule needs 1 h".

**Minor**
- Aurora alerts follow the same six-hour stale-forecast rule as every alert and never use another site's forecast; a level is recorded as sent only when notifications are on; a hand-edited "green" threshold lifts to yellow.
- Toggling Bright nights mid-evening restarts that night's alerts in the new mode instead of sending "Stand down. Clouds moving in".
- A bright night with no nautical darkness (Scotland at midsummer) keeps the Moon tile's real values.
- README: the privacy line names AuroraWatch UK; a note that the default quiet hours cover almost all of a midsummer night, so shorten them for summer aurora alerts.
- Version 0.3.1; product overview updated.

129 tests pass (6 new, including a bright plan from the planner straight through the alert engine); release build clean. The installed app is built from this branch.

**Still your call:** whether AuroraWatch UK's "correct colour" means their own traffic-light colours (see #12).

No-issue: fixes from the v0.3.0 final review, tracked by the v0.3 ledger.

## UAT

**UAT:** Run `scripts/test.sh` → 129 pass; About window shows 0.3.1; README "What it does" mentions that quiet hours cover most of a midsummer night for aurora alerts.

## #16: docs: v0.4 Jingo implementation plan

*merged 2026-09-24 · `docs/v0.4-plan` → `main`*

The implementation plan for the v0.4 Liquid Glass redesign, from the spec merged in #14. Nine serial tasks, each its own PR:

1. Tokens and the glass modifier with a solid fallback
2. SkyCore data: limiting factors, dew risk, viewability, frame fill, catalogue IDs
3. Clock bezel, headline block and reason line
4. Clear-sky bars, notice row and stat tiles
5. Best tonight cards and footer
6. Targets viewability timeline
7. Frame chip and titles
8. Targets header strip and sort, glass sidebar, filter switches with the Moon line
9. Accessibility pass (measured contrast), docs and 0.4.0

Rulings recorded in the plan where the spec left a gap:
- Limiting factors are computed from the score's own inputs and stored on the plan.
- "Best now" uses the current altitude only while darkness is under way.
- The Moon-washed badge becomes an amber chip.
- The stale footer keeps "Off the beat since" and adds the dot and age.

No-issue: planning document for the v0.4 spec (#14).

## UAT

**UAT:** Read docs/plans/2026-09-24-v0.4-jingo.md → nine tasks, each with its tests, code and a UAT line, covering every section of the v0.4 spec.

## #17: feat(app): v0.4 tokens and glass with solid fallback

*merged 2026-09-24 · `feat/v0.4-t1-glass` → `main`*

Task 1 of the v0.4 "Jingo" plan (docs/plans/2026-09-24-v0.4-jingo.md).

- `Tokens.swift` holds the spec §4 colour tokens. `Theme` now maps onto them, so existing views compile unchanged.
- `nightwatchGlass(in:fill:tint:)` applies Liquid Glass (`glassEffect`, `.regular` tinted) on macOS 26 or later with Reduce Transparency off. Otherwise it draws the solid fill. `GlassGroup` wraps groups in one `GlassEffectContainer`.
- Glass is on the popover panel, the six tiles and the Targets and dark-site cards. Settings controls take the system-blue tint.

Checks:
- 129 tests pass.
- The release build is clean.
- The task review found no issues.

I could not take a screenshot, because screen control was declined. The visual check is the UAT line below.

No-issue: implements task 1 of the v0.4 plan (#16).

## UAT

**UAT:** Open the menu-bar popover on macOS 26 or later → the panel, the six tiles and the Targets cards are frosted glass; turn on System Settings › Accessibility › Display › Reduce transparency → the same layout on a solid dark fill.

## #18: feat(skycore): v0.4 data: limiting factors, dew risk, viewability, frame fill, catalogue IDs

*merged 2026-09-24 · `feat/v0.4-t2-data` → `main`*

Task 2 of the v0.4 plan: the SkyCore data the new screens need (spec §6).

- `Planner.dewRisk` moves the dew rule into SkyCore: a temperature minus dew point spread under 2 °C is High, under 4 °C is Medium. The score uses it.
- `Planner.limitingFactors` lists each score term that lost more than a third of its weight, biggest first. It is stored as `NightPlan.limiting`, and `Copy.heldBack` turns it into "Held back by a 97% moon and high dew risk". A bright plan never blames the Moon.
- The score is refactored onto shared terms, with no change to any value. A test pins the 0.3.1 numbers.
- `RankedTarget` gains six fields:
  - `viewable` (the span inside the window above the minimum altitude)
  - nine `altitudeSamples`
  - `frameFill`
  - `typeName` ("Emission nebula")
  - `catalogueID` ("NGC 7000", "IC 1340", "C 9")
  - `commonName`
- Every catalogue ID follows one "{catalogue} {number}" pattern, per the handover.

Checks:
- 141 tests pass, 12 of them new.
- The release build is clean.
- The review's Important finding (addendum IDs) and two of its minors are fixed.

No-issue: implements task 2 of the v0.4 plan (#16).

## UAT

**UAT:** Run scripts/test.sh → 141 tests pass; open Targets → IDs read with one spacing pattern, e.g. "IC 1340", and nothing else looks different yet.

## #19: feat: v0.4 clock bezel, headline block and reason line

*merged 2026-09-24 · `feat/v0.4-t3-bezel` → `main`*

Task 3 of the v0.4 plan: the popover header, clock bezel and headline block (spec §5.1).

- **Bezel.** `Bezel.slots` (SkyCore) classifies the 60 ticks of a 12-hour face by the handover's tick rule, on the site's own clock. Each tick is clear, dark and partly cloudy, dark and cloudy, or daylight.
  - When darkness fits in 12 hours the face shows all of it.
  - When darkness is longer, as in an Home winter, the face shows the 12 hours round the clear window.
  - On a bright plan, "dark" means nautical darkness.
- **Score.** `ScoreBezel` draws the ticks, red with one shared glow across the window. The score sits inside with a 9 pt "SKY SCORE" caption, and screen readers get a sentence label.
- **Headline block.** It uses the handover type sizes. The amber-dot reason line, "Held back by a 97% moon and high dew risk", is hidden when nothing limits the score.
- **Header.** Eyebrow and meta line at 11 pt. The EQ tilt stays where the owner ruled.

Checks:
- 146 tests pass, 5 of them for the bezel. The review asked for one more centring test, and it was confirmed against a deliberately wrong face.
- The release build is clean.
- I could not take a screenshot; the visual check is the UAT line below.

No-issue: implements task 3 of the v0.4 plan (#16).

## UAT

**UAT:** Open the popover → the sky score sits in a 60-tick bezel whose ticks glow red across tonight's clear window, dim where it is dark but cloudy, faint in daylight; with a bright Moon up, the line under the window time reads "Held back by a N% moon".

## #20: feat: v0.4 clear-sky bars, notice row and stat tiles

*merged 2026-09-24 · `feat/v0.4-t4-bars-tiles` → `main`*

Task 4 of the v0.4 plan: clear-sky bars, the notice row and the stat tiles (spec §5.1).

- **`ClearSkyBars`.** A shared view with one column per hour of darkness. Fill is 100 − cloud. Every hour that overlaps a clear window is red with a glow. Each column has an hour label, with one peak label over the clearest hour and a sentence for screen readers. The Targets header reuses it in Task 8.
- **Notice row.** At most one line: the aurora status, else the Clearer sky link, which is now in text.primary because red means clear sky only.
- **`StatTile`.** Label over value; "No data" when a source is missing. The Dew risk tile turns amber when the risk is High, with an outline, a dot and "Dew heater advised". The detail view reuses the same tile.
- **Moon tile.** No label: the Moon, "N%", and "Sets 06:10", "Rises 22:14" or "Up all night", or just "Down tonight". This comes from the new `Planner.moonTonight`, measured over the plan's own darkness.

Checks:
- 150 tests pass.
- The release build is clean.
- The review's Important finding is fixed with a test: a clear first hour stayed grey when darkness clipped the window. Its moonrise minor is fixed the same way.

No-issue: implements task 4 of the v0.4 plan (#16).

## UAT

**UAT:** Open the popover → the cloud strip is now clear-sky bars (taller = clearer) with the window hours red; the Moon tile shows the Moon, "N%" and "Sets HH:MM"; on a damp night the Dew risk tile has an amber outline and "Dew heater advised".

## #21: feat: v0.4 best-tonight cards, notify switch, Patrol and stale badge

*merged 2026-09-24 · `feat/v0.4-t5-best-footer` → `main`*

Task 5 of the v0.4 plan: the Best tonight cards and the footer (spec §5.1).

- **Cards.** Each card shows the catalogue ID in bold, then the common name or type, then "Best HH:MM · N° up". The thumbnail has a 7 pt radius. "All targets →" is now text.primary, not red.
- **Footer.**
  - A switch labelled "Notify at HH:MM" (the pre-window time) or "Notify when clear", bound to the same setting as before.
  - "Patrol" ("Refresh" in plain wording) as a small glass-toned button.
  - The update line with its source. When the forecast is over six hours old it gains an amber dot and "{n} h ago", and keeps "Off the beat since HH:MM".
- The "Notify at" line under the window time is gone, because the switch carries it.

Checks:
- 151 tests pass.
- The release build is clean.
- The task review found no Critical or Important issues.

No-issue: implements task 5 of the v0.4 plan (#16).

## UAT

**UAT:** Open the popover → three cards read e.g. "NGC 7000 / North America Nebula / Best 21:30 · 72° up"; the footer switch reads "Notify at HH:MM" and turning it off stops alerts; Patrol refreshes and the update time changes.

## #22: feat: v0.4 viewability timeline on Targets cards

*merged 2026-09-24 · `feat/v0.4-t6-timeline` → `main`*

Task 6 of the v0.4 plan: the viewability timeline on every Targets card (spec §5.2, handover timeline table).

- The track spans tonight's clear window, or darkness when there is none. It carries a tick on each whole hour.
- The viewable span is lit from the dim red to the app red, following the real altitude curve (nine samples). `Planner.timelineStops` holds the gradient rule: the handover's u = (alt − 30)/(peak − 30), with the floor dropped to 10° below the peak for low targets such as the Moon and bright-night planets, so it never divides by zero.
- A white best-moment marker sits on the track.
- The captions read "Viewable 21:10–01:40" and "Best 23:20 · 64°". They read "Not in clear sky tonight" when there is no window, and "Viewable outside the clear window" when the target is only up outside it.
- Each card reads to screen readers as one sentence (spec §7), for example "NGC 7000 North America Nebula, viewable from 21:10 to 01:40, best at 23:20, 64 degrees up".

Checks:
- 153 tests pass.
- The release build is clean.
- The task review found no Critical or Important issues, and two of its minors are fixed.

No-issue: implements task 6 of the v0.4 plan (#16).

## UAT

**UAT:** Open Targets → every card shows a track across tonight's clear window with the viewable part lit red, brighter where the target is higher, a white dot at the best moment and "Viewable 21:10–01:40 · Best 23:20 · 64°" beneath.

## #23: feat: v0.4 frame-fill chip and card titles

*merged 2026-09-24 · `feat/v0.4-t7-chips-titles` → `main`*

Task 7 of the v0.4 plan: Targets follow-ons 1 and 2 (spec §5.3).

- **Frame chip.** The red "Fits frame" badge is now a neutral glass chip: "Fills 48% of frame", "Small in frame" or "Mosaic", or "Fits frame" when the size is unknown. It is hidden while "Fits my field of view" is on.
- **Moon-washed.** Now an amber warning chip with a Moon icon, since amber means a warning. The last non-token colour, `Theme.bad`, is removed.
- **Titles.** One pattern on every card: catalogue ID in text.primary, which never truncates ("IC 1340"), then the common name or type in text.secondary, which truncates first, then the magnitude. The magnitude is on every card, with "mag –" when unknown, per the handover's "every card or none".

Checks:
- 154 tests pass.
- The release build is clean.
- The task review found no Critical or Important issues, and its minor is fixed with a test.

No-issue: implements task 7 of the v0.4 plan (#16).

## UAT

**UAT:** Open Targets → titles read "IC 1340  Eastern Veil" with a magnitude on every card; the old red "Fits frame" badge is now a neutral "Fills N% of frame" chip that disappears when "Fits my field of view" is on; Moon-washed shows as an amber chip.

## #24: feat: v0.4 Targets header strip and sort, glass sidebar, filter switches

*merged 2026-09-24 · `feat/v0.4-t8-targets-chrome` → `main`*

Task 8 of the v0.4 plan: Targets follow-ons 3 to 5 (spec §5.3).

- **Header.** The sort sentence is replaced by the shared slim clear-sky strip and a Best now / Altitude / Size / Brightness control.
  - "Best now" sorts by altitude at this moment while darkness is under way, re-sorting every five minutes. Outside darkness it keeps the ranked order, since daytime altitudes mean nothing.
  - The header also shows the stale warning, and plain lines when there is no plan, no darkness, or no clear window.
- **Sidebar.** Glass, with a white glass highlight on the selected section. Screen readers hear the selected state, and the arrow keys move between sections.
- **Filters.** Switches in place of checkboxes, under an amber Moon line such as "Moon 62% · sets 06:10", so "Include Moon-washed" has context.
- **Near Moon.** An amber chip for targets within 15° of a Moon over half lit that is up tonight. Bright-night planets now carry their real separation from the Moon, where 0 used to be a placeholder.

The window toolbar is left as the system draws it.

Checks:
- 158 tests pass.
- The release build is clean.
- The task review's four Important findings are all fixed: Near Moon only appearing with the Moon down, the stale "Best now", sidebar accessibility, and the empty header with no plan.

No-issue: implements task 8 of the v0.4 plan (#16).

## UAT

**UAT:** Open Targets → the header shows a slim clear-sky strip and a Best now / Altitude / Size / Brightness control that reorders the cards; the sidebar is glass with a white highlight and the arrow keys move through it; the filters are switches under an amber "Moon N% · sets HH:MM" line.

## #25: docs: v0.4.0 docs, version, contrast tool, final-review fixes

*merged 2026-09-24 · `docs/v0.4-release` → `main`*

Task 9 of the v0.4 plan: docs, version 0.4.0, the contrast tool, and the fixes from the final whole-release review.

- **Version** 0.4.0 (build 7). The README and the product overview describe the redesign. UAT items 19 to 26 are added.
- **`scripts/contrast.swift`** captures the open popover without clicking (`screencapture -l`) and samples the bare glass in its side padding. It prints each text token's worst WCAG ratio and exits 1 under 4.5:1. Run it with the popover open over a white window (UAT 26), or pass `--wait 600` to have it wait for the popover.
- **Spec.** §7 records the solid-fallback contrast (14.9, 8.1 and 9.5 to 1), and §1 gains a status line for each criterion.
- **Fixes from the final review (on the most capable model):**
  - A Targets card's screen-reader sentence now includes its chips and magnitude. It had been dropping "Moon-washed" and "Near Moon".
  - The "Notify at HH:MM" switch reads "Notify when clear" when quiet hours would drop that nudge.
  - Tiles take the light tile tint on glass.
  - The sidebar drops a second glass layer.
  - The detail altitude is rounded like the cards.

**Not yet measured:** contrast on the live glass. I cannot open the popover, because screen control was declined. A simple model (the panel tint at 62% over a white window) suggests text.secondary could fall to about 2.5:1. Real glass may do better, but this needs measuring before the v0.4.0 tag. If it fails, the fix is raising the tint opacity in `Tokens.swift`.

Checks:
- 160 tests pass.
- The release build is clean.
- The whole-release review's two Important findings: one is fixed with a test; the other is the measurement above.

No-issue: implements task 9 of the v0.4 plan (#16).

## UAT

**UAT:** Open About → version 0.4.0; then open the popover over a white window and run `swift scripts/contrast.swift` → text.primary, text.secondary and status.warning each print "pass".

## #26: fix: v0.4 tile contrast, measured live

*merged 2026-09-25 · `fix/v0.4-tile-contrast` → `main`*

The live contrast check (UAT 26) found the tiles failing on macOS 27. Tiles drawn as a second glass layer, tinted surface.tile, rendered as #5A5D63. That left the grey labels at 2.9:1 and the amber "Dew heater advised" at 3.5:1. The panel itself passed.

The tiles are now the handover's plain surface.tile fill on the glass panel, with no second glass layer. The detail view's tiles, which share the component, follow.

| Surface | text.primary | text.secondary | status.warning |
|---|---|---|---|
| Panel | 11.4:1 | 6.2:1 | 7.3:1 |
| Tiles before | 5.4:1 | 2.9:1 | 3.5:1 |
| Tiles now (#3B3D43) | 8.9:1 | 4.8:1 | 5.7:1 |

The figures come from `screencapture -l` of the open popover over a white page on the owner's Mac, after reinstalling from this branch. Spec criterion 1 and §7 are amended to match.

Checks:
- 160 tests pass.
- The release build is clean.

No-issue: fixes the v0.4 contrast criterion found by UAT 26.

## UAT

**UAT:** Open the popover → the six tiles are a shade lighter than the panel (not the pale grey of the first 0.4.0 build) and their grey labels read clearly; run `swift scripts/contrast.swift --wait 60` from this session or Terminal and open the popover → all three tokens print "pass".

## #27: fix: tiles in a row share the tallest tile's height

*merged 2026-09-25 · `fix/v0.4-tile-heights` → `main`*

Owner request: the Dark, Seeing, Wind and Transparency tiles should be as tall as the Moon and Dew risk tiles.

- A shared `TileRow` gives every tile in a row the tallest tile's height. It is an HStack at its ideal height, and each tile's frame stretches to fill it.
- Labels stay top-left, as on the Dew risk tile.
- The popover's two rows use it, and so does the target detail view's row of four, in place of its grid.

Checks:
- Live check: the popover was captured on the owner's Mac after reinstalling from this branch. Both rows' tiles are the same height: Dark, Moon and Seeing in the first; Wind, Dew risk and Transparency in the second.
- `scripts/contrast.swift` on the same capture still passes: 11.4, 6.2 and 7.3 to 1.
- 160 tests pass.
- The release build is clean.

No-issue: owner-requested layout fix to v0.4.

## UAT

**UAT:** Open the popover → in each row of tiles all three tiles are the same height (Dark, Moon, Seeing; then Wind, Dew risk, Transparency), labels top-left.

## #28: chore: version 0.4.1

*merged 2026-09-25 · `chore/v0.4.1` → `main`*

Version 0.4.1 (build 8), with a product overview release row. It covers the equal-height tile rows (#27) and the live-measured tile contrast fix (#26).

No-issue: version bump for the v0.4.1 tag requested by the owner.

## UAT

**UAT:** Open About → version 0.4.1.

## #29: docs: v0.5 "The Fifth Elephant" spec: forecast agreement

*merged 2026-09-25 · `docs/v0.5-spec` → `main`*

Spec for v0.5: the forecast agreement signal from the Product Direction Synthesis (Direction A), approved by the owner on 25 September 2026.

- On a signed build, each patrol also fetches Open-Meteo for the active site as a second opinion. Apple Weather stays primary and still drives the verdict, score and bars.
- One line in the popover and in the heads-up and window-opening notifications says what Open-Meteo thinks of tonight:
  - "Open-Meteo agrees"
  - "Open-Meteo sees cloud from 23:00"
  - "Open-Meteo sees no clear window"
  - "Open-Meteo agrees: no clear window"
  - "Open-Meteo has a clear run 23:00–02:00"
- An opt-in setting, "Alert only when Open-Meteo agrees", holds back an alert when Open-Meteo would not meet the go rule inside the window.
- Nothing is logged. The second opinion lives in the forecast cache and is replaced each patrol.
- Unsigned builds show no line, since they already run on Open-Meteo.

Decisions for the owner to check in review (§2): the wording above; the second opinion covers the home site only, not the dark sites; unsigned builds get no 7Timer-based second opinion.

No-issue: planning document for v0.5.

## UAT

**UAT:** Read docs/specs/2026-09-25-v0.5-fifth-elephant-agreement-design.md → the five line wordings, the opt-in setting and the "nothing logged" rule match what you want; merge to start the plan and build.

## #30: docs: v0.5 "The Fifth Elephant" implementation plan

*merged 2026-09-25 · `docs/v0.5-plan` → `main`*

Plan for the v0.5 spec (#29): five serial tasks, each its own PR.

1. Fetch Open-Meteo beside Apple Weather as a second opinion, for the active site only.
2. Assess agreement under the go rule.
3. The popover line and notification wording.
4. The opt-in "Alert only when Open-Meteo agrees", with a lenient config decode.
5. Docs and 0.5.0.

Review Focus pins five failure modes with tests:
- a missing Open-Meteo hour hides the line;
- a 0.4 config keeps its alert settings;
- the "cloud from" time is clamped to the window;
- the setting never blocks an unsigned build;
- dark-site patrols make no extra calls.

No-issue: planning document for v0.5 (#29).

## UAT

**UAT:** Read docs/plans/2026-09-25-v0.5-fifth-elephant.md → five tasks with tests, code and a UAT line each, covering every section of the v0.5 spec.

## #31: feat(skycore): v0.5 Open-Meteo second opinion beside Apple Weather

*merged 2026-09-25 · `feat/v0.5-t1-second-opinion` → `main`*

Task 1 of the v0.5 plan (#30): Open-Meteo as a second opinion (spec §3.1).

- When Apple Weather answers, `ForecastService.fetch` also fetches Open-Meteo for the same site. It keeps each hour's cloud as `Forecast.secondOpinion`.
- Apple Weather still supplies every hour the app uses. A failed second fetch never fails the forecast.
- When Apple Weather fails, or the build is unsigned, Open-Meteo is already primary and there is no second opinion.
- Dark-site patrols pass `secondOpinion: false`, so they make no extra calls.
- Nothing is logged. A 0.4 `forecast.json` still decodes.

Checks:
- 165 tests pass, 5 of them new.
- The release build is clean.
- The task review found no Critical or Important issues.

No-issue: implements task 1 of the v0.5 plan (#30).

## UAT

**UAT:** Run scripts/test.sh → 165 pass; after a Patrol on the signed build, ~/Library/Caches/Nightwatch/forecast.json contains "secondOpinion" with source "Open-Meteo".

## #32: feat(skycore): v0.5 agreement assessment

*merged 2026-09-25 · `feat/v0.5-t2-assessment` → `main`*

Task 2 of the v0.5 plan: assessing Open-Meteo's agreement with tonight (spec §3.2, amended here).

`Planner.agreement` applies the same go rule to Open-Meteo's hours, and the result is stored on `NightPlan.agreement`:
- **All clear in Apple Weather's window:** "agree".
- **Clear enough, but cloud after its clear run begins:** "cloud from HH:MM".
- **Cloudy only before its run:** "clears from HH:MM". This is new, from the review.
- **Not clear enough inside the window but clear elsewhere tonight:** "clear run HH:MM–HH:MM". This is also new from the review; it had read "no clear window".
- **Clear nowhere tonight:** "no clear window".
- **With no Apple window:** "agrees: no clear window", or Open-Meteo's clear run.

The line is nil, and so hidden, without a second opinion, when an hour is missing, or on a bright night with no window. `agreementHolds` is false when Open-Meteo is not clear enough inside the window. The opt-in in Task 4 uses it.

Checks:
- 181 tests pass, 16 of them for agreement.
- The release build is clean.
- The review's three Important findings are fixed with tests that failed first.
- The spec's §3.2 and §4 are amended to match.

No-issue: implements task 2 of the v0.5 plan (#30).

## UAT

**UAT:** Run scripts/test.sh → 181 pass, including the 16 agreement tests (agree, cloud later, clearing later, clear elsewhere, no window, missing hour, bright window, cache round trip).

## #33: feat: v0.5 agreement line in the popover and alerts

*merged 2026-09-25 · `feat/v0.5-t3-line` → `main`*

Task 3 of the v0.5 plan: the agreement line (spec §4).

- `Copy.agreementText` gives the six spec wordings: "Open-Meteo agrees", "…sees cloud from 23:00", "…sees it clear from 21:00", "…sees no clear window", "…agrees: no clear window" and "…has a clear run 23:00–02:00".
- `Copy.agreementWarns` picks an amber dot for a disagreement and a tick for agreement.
- The popover shows the line under "Held back by" in the window branch, and under the reason in the no-window branch. It is 10 pt secondary text, and never red.
- The heads-up and the window-opening notification end with the same sentence ("… Open-Meteo agrees."). The tomorrow preview and the stand-down do not carry it.

Live evidence: the installed signed app's `forecast.json` (fetched 09:56 UTC) has `cloudSource: "Apple Weather"` and a `secondOpinion` of 72 Open-Meteo hours. The popover screenshot is being captured when the owner next opens it.

Checks:
- 183 tests pass.
- The release build is clean.
- The task review found nothing to fix.

No-issue: implements task 3 of the v0.5 plan (#30).

## UAT

**UAT:** Open the popover → under the window time a line reads "Open-Meteo agrees" with a tick, or an amber-dot line such as "Open-Meteo sees cloud from 00:00"; the evening heads-up ends with the same sentence.

## #34: feat: v0.5 opt-in "Alert only when Open-Meteo agrees"

*merged 2026-09-25 · `feat/v0.5-t4-setting` → `main`*

Task 4 of the v0.5 plan: the opt-in "Alert only when Open-Meteo agrees" (spec §5).

- `AlertSettings.requireAgreement` is off by default.
- When it is on and Open-Meteo is not clear enough inside tonight's window, the evening heads-up and the window-opening alert are held back. That means "sees no clear window", or clear only at another time. The alert stays pending, so it fires on a later patrol if the sources come round.
- The stand-down, the tomorrow preview and quiet hours are unchanged.
- With no second opinion (unsigned builds), the setting never blocks anything.
- `AlertSettings` now decodes leniently, so a 0.4 config keeps every alert setting.
- Settings › Alerts has the toggle. It is disabled, with "Needs Apple Weather (signed build)", when there is no second opinion.

Live check: the installed build starts on the owner's existing config, Home, with every alert setting unchanged.

Checks:
- 187 tests pass.
- The release build is clean.
- The task review found no issues. Its one suggestion, an encoder round-trip test, is added.

No-issue: implements task 4 of the v0.5 plan (#30).

## UAT

**UAT:** Settings › Alerts shows "Alert only when Open-Meteo agrees" (enabled on the signed build, off by default); with it on, a night where Open-Meteo sees no clear window in Apple's window sends no heads-up.

## #35: docs: v0.5.0 docs, version, final-review fixes

*merged 2026-09-25 · `docs/v0.5-release` → `main`*

Task 5 of the v0.5 plan: docs, version 0.5.0, and the fixes from the final whole-release review.

- **Version** 0.5.0 (build 9). The README, product overview and UAT items 27–29 describe the agreement line, all six wordings, and the setting. The spec status reads "built in v0.5.0".
- **Fixes from the final review (on the most capable model):**
  - **Midnight gap.** Open-Meteo's data starts at 00:00 local, so just after midnight the line vanished while you were out. The second-opinion request now includes the previous day.
  - **Bright nights.** A bright night with a cloudy window no longer suggests "a clear run" at a time with no Moon or planet up. It reads "no clear window".
  - **The Settings toggle.** It is keyed on the build's source (Apple Weather), not on one fetch, so a single failed Open-Meteo call doesn't grey it out. A toggle that is on can always be turned off.
  - **Docs.** They list every wording and name the nudge.

Live evidence: on the owner's Mac, the signed app's `plan.json` for 25 September holds `agreement: agreeNoWindow`. Apple Weather and Open-Meteo each have only two clear hours tonight, so neither sees a 3-hour window, and the line reads "Open-Meteo agrees: no clear window".

Checks:
- 189 tests pass.
- The release build is clean.
- The final review found no Critical or Important issues. Its four minors are fixed, two of them with tests that failed first.

No-issue: implements task 5 of the v0.5 plan (#30).

## UAT

**UAT:** Open About → version 0.5.0; open the popover → tonight shows "Open-Meteo agrees: no clear window" under the reason (or the line for tonight's forecast), in grey with a tick.

## #36: docs: v0.6 "Night Watch" spec: desktop widgets

*merged 2026-09-25 · `docs/v0.6-spec` → `main`*

Spec for v0.6: desktop widgets from the approved mockups.

- Small, medium and large widgets, as mocked, plus the no-window, bright, stale and disagree states.
- The widget draws a snapshot the app writes after each patrol. It never fetches weather and never disagrees with the popover.
- The bezel, bars and tokens move into a shared `NightwatchUI` library, so the widget and popover look the same.
- Clicking a widget opens the Targets window; a target row opens that target.
- A committed xcodegen `project.yml` builds the widget when Xcode is present. The Command Line Tools build still ships the app without it.

**For your review:**
- This is the first part of Nightwatch that needs Xcode.
- The spike (§4) must first confirm a few things against your developer account:
  - that a menu-bar app's widget shows in the gallery;
  - how the app and widget share the snapshot, which may need an App Group registered on your App ID;
  - that click-through works.
- The spike needs you once, to add the widget from the desktop gallery.

No-issue: planning document for v0.6.

## UAT

**UAT:** Read docs/specs/2026-09-25-v0.6-night-watch-widgets-design.md → the three-layer roles, the snapshot approach, the Xcode build rule and the spike list match what you want; merge to start the spike.

## #37: docs: v0.6 spec: widget spike results

*merged 2026-09-25 · `docs/v0.6-spike-results` → `main`*

Records the v0.6 widget spike's results in spec §4. All four unknowns are answered:

1. A menu-bar-only app's widget appears in the desktop gallery.
2. The app and widget share a snapshot through an App Group named with the team ID. It needs no portal registration, and the account is unchanged.
3. Clicking the widget, and a link inside the large widget, both deliver a URL to the app (`nwspike://targets`, `nwspike://target/NGC7000`).
4. A dark widget renders on the macOS 27 desktop. Desktop widgets must be switched on in System Settings.

No-issue: spike findings for the v0.6 spec (#36).

## UAT

**UAT:** Read spec §4 "Spike results" → it matches what you saw: the widget showed "Hello from the app" on the desktop, and your clicks reached the app.

## #38: feat: app icon (star over a red-lit horizon); version 0.5.1

*merged 2026-09-25 · `feat/app-icon` → `main`*

Adds Nightwatch's first app icon, from the artwork the owner chose: a star above a red-lit horizon. It is recognisable at the 22-point size of the widget gallery's app list, where the blank default icon was easy to miss.

- **Source:** `Resources/AppIcon/Nightwatch.icon`, an Icon Composer document holding the owner's art as a 1024 px full-bleed image.
- **With Xcode:** `scripts/build-app.sh` compiles it with `actool` into a Liquid Glass icon (`Assets.car`) plus a classic `.icns`, and sets `CFBundleIconName` and `CFBundleIconFile`. macOS 26 and later then show the icon itself, not inside a grey tile.
- **Without Xcode (Command Line Tools only):** `scripts/make-icns.swift` builds a classic `.icns`, with the art in Apple's rounded tile. If that ever failed, the build carries on with the default icon rather than stopping.
- Version 0.5.1; the README and product overview are updated.

Live evidence:
- The installed app on the owner's Mac (0.5.1) has `Assets.car`, `Nightwatch.icns` and `CFBundleIconName = Nightwatch`.
- `NSWorkspace.icon(forFile:)` renders it as a clean Liquid Glass icon, with no grey tile.
- The fallback was checked on the Command Line Tools path: it produces the full 10-image icon set.

Checks:
- 189 tests pass.
- The review's one Important finding (the fallback could abort the build) and its minor are fixed.

No-issue: owner request, an app icon so Nightwatch is findable in the widget gallery.

## UAT

**UAT:** Look at /Applications in Finder (or Spotlight "Nightwatch") → the app shows the star-over-horizon icon, not a blank one; About shows version 0.5.1.

## #39: feat: porthole app icon; version 0.5.2

*merged 2026-09-25 · `feat/icon-porthole` → `main`*

Replaces the app icon's artwork with the owner's favourite, reworked to be full-bleed for macOS 27: a porthole onto the night sky with a red-lit horizon. Only `Resources/AppIcon/Nightwatch.icon/Assets/Nightwatch.png` changes (1254 px source resized to 1024). The build path from #38 is unchanged.

Live evidence:
- The installed app on the owner's Mac is 0.5.2, built through the `actool` path ("Icon: Liquid Glass (actool) plus .icns").
- `NSWorkspace.icon(forFile:)` renders the porthole as a clean Liquid Glass icon, with no grey tile.
- At the 22-point size of the widget gallery list, the ring, red horizon and colourful sky stay recognisable. The star itself is too small to see at that size.

Checks: 189 tests pass.

No-issue: owner's chosen icon artwork.

## UAT

**UAT:** Look at Nightwatch in /Applications or Spotlight → the porthole icon; About shows 0.5.2.

## #40: docs: v0.6 "Night Watch" implementation plan

*merged 2026-09-25 · `docs/v0.6-plan` → `main`*

Plan for the v0.6 widgets (spec #36, spike results #37). Five serial tasks:

1. A shared `NightwatchUI` library (bezel, bars, tokens), with no visual change.
2. `WidgetSnapshot`, written after each patrol.
3. The widget extension, built by `xcodebuild` from an xcodegen `project.yml` and embedded in the SwiftPM-built app.
4. Click-through to Targets and to a target.
5. Docs and 0.6.0.

A Command Line Tools-only build still produces the app, without the widget.

No-issue: planning document for v0.6 (#36).

## UAT

**UAT:** Read docs/plans/2026-09-25-v0.6-night-watch.md → five tasks, each with tests or a live check and a UAT line, covering the spec.

## #41: fix: Targets sidebar clicks; All targets as a button

*merged 2026-09-25 · `fix/sidebar-clicks-and-all-targets` → `main`*

Two owner-reported issues.

- **Sidebar clicks landed on the wrong row.** Clicking "Planets and Moon" selected "Constellations". v0.4's hand-built sidebar (a column of buttons) drew its rows about two rows below where it took clicks. The Targets window now uses the native sidebar `List(selection:)`, which also brings back arrow keys, type-to-select and VoiceOver selection. The selected row uses the system highlight rather than v0.4's white glass one. The owner confirmed the clicks now work.
- **"All targets" was easy to miss.** It is now a filled button, in one shared `SecondaryButtonStyle` used by Patrol too, so the two always match. The count was tried and dropped at the owner's request.

Live evidence: a popover capture on the owner's Mac shows the filled "All targets" button beside "UP TONIGHT", in the same style as Patrol. Contrast is unchanged at 11.7:1 and 6.3:1.

Checks: 189 tests pass, and the release build is clean.

No-issue: owner-reported UI fixes.

## UAT

**UAT:** Open Targets and click each sidebar section → the clicked row is selected; open the popover → "All targets →" is a filled button like Patrol and opens Targets.

## #42: refactor: v0.6 NightwatchUI library and data-driven bars

*merged 2026-09-25 · `refactor/v0.6-t1-nightwatchui` → `main`*

Task 1 of the v0.6 plan (#40): the shared `NightwatchUI` library. This is a refactor with no visual change intended.

- **New SwiftPM library target `NightwatchUI`:** Tokens, ScoreBezel, WarningDot, and `TargetGroup.symbolName`. The app and the coming widget share it.
- **Data-driven bars:** `ClearSkyBars` now draws `ClearSkyBar` data, built by `Planner.clearSkyBars` in SkyCore with its label from `Copy.barsLabel`. The widget can draw the bars without a `NightPlan`.
- **No-window reason:** it moves into SkyCore as `Planner.noWindowReasonText`, for the same reason.
- **`BezelSlot`** is now Codable.

Checks:
- 192 tests pass, 3 of them new: they pin the old bar rule, the label and the reason.
- The release build is clean, including a Command Line Tools-only build.
- The task review confirmed behaviour is identical to the deleted code. Its only fix, unused imports, is done.

No-issue: implements task 1 of the v0.6 plan (#40).

## UAT

**UAT:** Open the popover and Targets → they look exactly as in 0.5.2 (bezel, bars with hour labels and peak %, tiles, header strip).

## #43: feat(skycore): v0.6 WidgetSnapshot, written after each patrol

*merged 2026-09-25 · `feat/v0.6-t2-snapshot` → `main`*

Task 2 of the v0.6 plan: `WidgetSnapshot` (SkyCore) and writing it after each patrol.

- **What it holds:** everything the widget will draw, as plain values:
  - the headline, window and reason, in exactly the popover's words
  - the Open-Meteo line
  - the 60 bezel slots and the bars, with their screen-reader sentences
  - the best three targets
  - tomorrow's window
  - the notify text
  - `staleText(now:)` gives "Forecast N h old" after six hours, judged when the widget draws, not when the file was written.
- **Where it's written:** the Store writes `widget.json` into the App Group container named by the `NightwatchAppGroup` Info.plist key, then reloads WidgetKit. Builds without the key write nothing. Task 3's build script adds the key.

Checks:
- 199 tests pass, 7 of them new: clear night, no window, no darkness, bright night, agreement, staleness, JSON round trip.
- The release build is clean, with Xcode and with the Command Line Tools only.
- The review's Important finding (a Tomorrow line on no-darkness nights) is fixed with a test that failed first.

No-issue: implements task 2 of the v0.6 plan (#40).

## UAT

**UAT:** Run scripts/test.sh → 199 pass, including the seven WidgetSnapshot tests.

## #44: feat: Nightwatch desktop widgets (small, medium, large)

*merged 2026-09-25 · `feat/v0.6-t3-widget` → `main`*

Task 3 of the v0.6 plan: the Nightwatch desktop widget in small, medium and large sizes.

- **What it draws:** the snapshot the app writes after each patrol (Task 2), so it always matches the popover and never fetches anything.
  - Small: the sky-score bezel, a one-line verdict and one supporting line.
  - Medium: adds the headline, the reason, the Open-Meteo line and the clear-sky bars.
  - Large: adds the hour labels, the best three targets, the notify time and an "Updated · source" footer. When the forecast is stale, the footer shows the stale warning instead.
- **How it's built:** `Widget/project.yml` (xcodegen) builds the extension with `xcodebuild`, pinned to the root `Package.resolved`. `scripts/build-app.sh` then embeds it at `Contents/PlugIns` before signing the app.
  - The app and the widget share a team-prefixed App Group, which needs no portal registration.
  - Without Xcode or xcodegen, the build says why it skipped the widget and builds the app exactly as before.
- **The gallery** shows a sample night until the app has written a snapshot.

Checks:
- 201 tests pass. The new ones cover the snapshot's new fields, decoding an older `widget.json`, and the gallery sample.
- `codesign --verify --deep --strict` passes on the installed app. Both bundles carry the same App Group.
- Layout heights were measured with NSHostingView across 7 states, including stale, disagreeing and no darkness. The worst cases are small 131 of 138 pt, medium 134 of 138 and large 348 of 350.
- Checked live on the owner's desktop in all three sizes.
- The review's two Important findings (the large layout overflowing, and the small widget sitting off-centre) and all ten Minor findings are fixed.

Also: the Targets, Settings and About windows now open centred by default (owner report). Clicking the widget opening Targets is Task 4.

No-issue: implements task 3 of the v0.6 plan (#40).

## UAT

**UAT:** Run scripts/build-app.sh → right-click the desktop › Edit Widgets… › Nightwatch → add small, medium and large → each shows tonight's score and verdict with nothing cut off, and the small one is centred.

## #45: feat: widget click-through to Targets and to a target

*merged 2026-09-25 · `feat/v0.6-t4-clickthrough` → `main`*

Task 4 of the v0.6 plan: clicking the desktop widget opens Nightwatch.

- **`WidgetLink` (SkyCore):** `nightwatch://targets` and `nightwatch://target/<id>`. Ids are percent-encoded with the RFC 3986 unreserved set, so a "/", space or "+" in an id survives.
- **The app:** declares the `nightwatch` URL scheme, and an app delegate receives the links. A click that launches the app waits until boot sets the handler, so it isn't lost.
- **The menu-bar icon** opens and activates the Targets window on any request, because it is the one view that is always alive.
- **Targets:** a target link opens that target's group and its detail page. A plain link brings the window forward without changing the section.
- **Also:** `NSApp.activate(ignoringOtherApps:)`, deprecated on macOS 14, is replaced with `NSApp.activate()`. Checked live: the window still comes to the front over other apps.

Checks:
- 202 tests pass, including the new `widgetLinkRoundTrip`. The release build is clean.
- Live test: `open nightwatch://targets` opened Targets, centred and frontmost. `open nightwatch://target/NGC0147` opened NGC 147's detail with a Galaxies back button.
- The review found no Critical or Important issues. Its three Minor notes are fixed.

No-issue: implements task 4 of the v0.6 plan (#40).

## UAT

**UAT:** Click the widget → the Targets window opens in front, centred. On a clear night, click a target row on the large widget → that target's detail opens.

## #46: v0.6.0 Night Watch: version, docs and release-review fixes

*merged 2026-09-25 · `feat/v0.6-t5-release` → `main`*

Task 5 of the v0.6 plan: version 0.6.0 "Night Watch", the docs, and the fixes from the final whole-release review.

- **Version:** 0.6.0, build 12, the same in the app and the widget.
- **Docs:**
  - The README describes the widgets and what clicking does, and names 0.6 "Night Watch", with "Thud!" and "Snuff" next.
  - The product overview gets a Desktop widgets paragraph, the new test count (202) and a 0.6.0 release row.
  - `docs/uat.md` gets items 30 to 36.
  - The spec's status is now "built in v0.6.0".
- **Fixes from the final review:**
  - **Important:** the large widget's "Updated" time now uses the popover's clock: the site's time zone, 24-hour. The snapshot carries it, with a test.
  - After a site change, the widget stops showing the old site's night until the new forecast arrives.
  - An unsigned build now says why the widget was skipped.
  - Overview wording: the medium widget shows the window too, and "no iPhone app or iPhone widget".

Checks:
- 202 tests pass, and older `widget.json` files still decode.
- The release build shows no warnings.
- The installed app reports 0.6.0.
- The final review's verdict was SHIP. All five of its findings are fixed here.

No-issue: implements task 5 of the v0.6 plan (#40).

## UAT

**UAT:** Open About → version 0.6.0. The README explains adding the widget and turning on desktop widgets. The large widget's "Updated HH:MM" matches the popover's update time.

## #47: feat: aurora line in AuroraWatch UK's own colours

*merged 2026-09-25 · `fix/aurora-colours` → `main`*

The popover's aurora line now uses AuroraWatch UK's own colours, as published in its status-descriptions list: yellow #ffff00, amber #ff9900, red #ff0000 (and green #33ff33, which never shows, because the lowest threshold is yellow). This is the owner's ruling of 25 September 2026.

- Before: the line used the night palette, so "Aurora: amber" was drawn in the app's red and "Aurora: yellow" in amber. The word and the colour disagreed.
- `AuroraLevel.hex` in SkyCore holds the four values, with a test.
- The product overview and UAT item 18 are updated.

Checks: 203 tests pass, the release build shows no warnings, and the app is installed. Tonight's AuroraWatch status is green, so the line is not showing and could not be checked live.

No-issue: owner ruling on aurora colours (pending since v0.3).

## UAT

**UAT:** Settings › Aurora on, threshold Yellow. On a night when AuroraWatch UK reports yellow or above → the popover's aurora line is in AuroraWatch's colour for that level (for example "Aurora: amber" in orange #ff9900).

## #48: release: v0.6.1 Night Watch, patch 1

*merged 2026-09-25 · `release/v0.6.1` → `main`*

Version 0.6.1, build 13, in both the app and the widget, plus the product overview's release row. The one change since 0.6.0 is the aurora line in AuroraWatch UK's own colours (#47).

Checks: 203 tests pass.

No-issue: release bump requested by the owner ("Tag it").

## UAT

**UAT:** Run scripts/build-app.sh → About shows version 0.6.1.

## #49: feat: constellation artwork for all 88 constellations (v0.6.2)

*merged 2026-09-25 · `feat/constellation-art` → `main`*

The owner's constellation artwork replaces the stick figures in Targets, for all 88 constellations (v0.6.2).

- **Cards and detail page:** the figure layer with the star-plot layer on top, fitted and not cropped. The detail page no longer shows "dashed = your field of view" for constellations.
- **Shipping:** 512 px HEIC with transparency, 4.3 MB for all 176 files, in `Resources/Constellations`. `build-app.sh` copies them into the app only; the widget doesn't need them.
  - In a side-by-side on the card background, quality 80 couldn't be told apart from the 1024 px originals.
- **`scripts/import-constellations.sh <folder>`** regenerates the files from the owner's `manifest.json`. It's deterministic: a re-run changed no files.
- **Removed:** the stick-figure view, `Constellation.unwrappedLines` and `Store.constellation(_:)`, which nothing else used.
- **Credits:** NOTICE and the product overview credit the artwork (MIT) and the d3-celestial star lines (BSD-3).
- **Version:** 0.6.2, build 14, in the app and the widget. The release row is added and UAT item 37 is new.

Checks:
- 203 tests pass. The new `everyConstellationHasArtwork` test checks that every catalogue constellation has both layers and that there are no extra files.
- The release build is clean.
- Live: `open nightwatch://target/Cyg` and `/Lac` show the artwork on the detail page.
- Review: the Critical finding (artwork loaded in `body` on every redraw) is fixed. The artwork now loads once per card in the thumbnail task. The two Important findings are fixed: filenames with spaces in the import script, and `.DS_Store` in the test.

No-issue: owner-supplied constellation artwork, design approved in conversation.

## UAT

**UAT:** Open Targets › Constellations → every card shows its figure with the star points on top, not a stick drawing → open one → the same art, larger, with no field-of-view note.

## #50: feat: stand down only when both forecasts lose the window; Hold fire when they split (v0.6.3)

*merged 2026-09-25 · `feat/less-certain-alert` → `main`*

After a heads-up or nudge, the follow-up message now matches what the two forecasts say (owner ruling, 25 September 2026). This is v0.6.3.

- **Both lose the window** (or there is only one forecast): "Stand down. Clouds moving in", with "Apple Weather and Open-Meteo both see cloud."
- **They split:** "Hold fire. Forecasts disagree" (plain wording: "Less certain. Forecasts disagree"), saying what each sees. For example, "Apple Weather now sees cloud. Open-Meteo has a clear run 23:00–02:00."
  - Where only Open-Meteo doubts, it is sent only with the opt-in "Alert only when Open-Meteo agrees" on.
- **Limits:**
  - At most one "Hold fire" a night.
  - If the forecasts agree again after the nudge has gone, nothing is sent again.
  - Nothing is sent after the window has closed.
  - After a real stand-down, a clearing sky still sends the nudge.
- **Before this change:** a stand-down went out whenever Apple Weather lost the window, even when Open-Meteo still saw clear sky.
- **Docs:** the spec §6 wording table, the product overview and UAT item 38. Version 0.6.3, build 15.

Checks:
- 212 tests pass, 9 of them new. They cover both lose, each kind of split, after a go, recovery, flip-flopping, after the window, the downgrade switch and quiet hours.
- The release build is clean.
- The review found no Critical issues. Its two Important findings are fixed with tests: repeated "Hold fire"/"All's well" when forecasts flip-flop, and alerts after the window. The Minor findings are fixed too: the force unwrap, the missing tests, and the docs saying "after a heads-up or nudge".
- Known limit: a 0.6.2 build can't read a state file with the new stage, so rolling back resets that night's alerts.

No-issue: owner ruling on the stand-down wording, given in conversation.

## UAT

**UAT:** On a signed build, after a heads-up, when only one forecast loses the window → one "Hold fire. Forecasts disagree" notification saying what each sees. When both lose it → "Stand down. Clouds moving in" / "Apple Weather and Open-Meteo both see cloud."

## #51: feat: full-window target detail pages (v0.6.4)

*merged 2026-09-25 · `feat/fullbleed-detail` → `main`*

Full-window target detail pages, as in the mockup the owner approved (v0.6.4).

- **Layout:** the image fills the window and the text sits on it in black caption boxes: a back pill, a field-of-view pill, and a bottom caption with the name, type and coordinates.
  - On a clear night the caption adds the four tiles and a labelled altitude chart: sunset to sunrise, the window shaded, the minimum altitude dashed, the curve red only where the target is up inside the window, and a dot at the best moment.
- **Survey photos** fill the page at 1600 px; hips2fits serves that size. The photo is centred on the clear space between the top bar and the caption.
  - For an object bigger than the field of view, the photo is fetched with 1.6× more sky, so the dashed box sits wholly inside that clear space. This is the owner's report that it went behind the caption.
- **The Moon, planets and constellation artwork** are fitted above the caption.
- **Cache:** card image names are unchanged, now in SkyCore with a test. Detail images are pruned after 30 days. The large fetch gets a 45 s timeout.
- **Small widget:** the system margins are applied by the view and made symmetric (Apple's `contentMarginsDisabled` pattern). **This did not cure the owner's report of the widget sitting a few points left of centre.** The view measures centred offscreen, and the cause is still open (UAT 40).
- **Version:** 0.6.4, build 16.

Checks:
- 214 tests pass. The release build is clean.
- Live: NGC 1491 fills the page with "Shown at your field of view". NGC 7000's dashed box is centred in the clear space. Cassiopeia and Saturn are fitted above the caption.
- Not seen live: the tiles and chart, because there is no clear window tonight.
- Review: no Critical findings. All three Important findings are addressed:
  - The previous target's late image no longer lands on a new page.
  - Long names no longer overflow a narrow caption.
  - The widget fix is not claimed.
  - All six Minor findings are fixed too.

No-issue: owner-approved detail-page mockup, given in conversation.

## UAT

**UAT:** Targets → open NGC 1491, NGC 7000, Cassiopeia and Saturn → each image fills the page with its text in black caption boxes, and NGC 7000's dashed box sits wholly above the caption.

## #52: fix: dark-site button says Observe from here

*merged 2026-09-25 · `fix/observe-from-here` → `main`*

The dark-site card button now says **"Observe from here"** in both wording modes. It used to say "Use as beat" ("Use as site" in plain wording).

The owner's ruling: the Pratchett references can only go so far before they lose people. The button still does the same thing: it saves the site and makes it the active site for the whole app.

- Updated: README, the product overview (including the 0.6.4 release row), UAT item 11, and a new row in spec §6 recording that this button is plain in both modes.
- "Beat" stays as the saved-site noun elsewhere, per spec §6.

Checks: 214 tests pass, the release build is clean, and the app is installed. The button wasn't seen live: a relaunch opens Targets on Nebulae, and I can't click through to Dark sites.

No-issue: owner request in conversation.

## UAT

**UAT:** Targets › Dark sites → every card's button reads "Observe from here" → click it → the popover header changes to that site.

## #53: fix: build-app.sh restarts the widget process on install

*merged 2026-09-25 · `fix/widget-reload` → `main`*

`scripts/build-app.sh` now ends the widget's process on install, so macOS relaunches it from the new copy.

- **Found 25 September 2026:** macOS keeps a widget extension's process alive across reinstalls and keeps drawing with the code it first loaded. On the owner's Mac the widget process had been running since 12:55. The desktop was still showing that build three hours and several installs later.
- **Why this explains the off-centre widget:** that was the old top-left layout, from before the centring fix at about 13:15. None of the later widget changes had reached the desktop.
- **Also:** unregistered the leftover NWSpike test widget, which was still listed in the gallery from the spike build in the scratch folder, and deleted that build.
- UAT item 40 is updated.

Checks: installing now leaves no stale widget process, and macOS starts it fresh on the next draw. The owner still needs to confirm on the desktop that the small widget is centred.

No-issue: stale widget process found while diagnosing the owner's off-centre report.

## UAT

**UAT:** Run scripts/build-app.sh → the small Nightwatch widget on the desktop redraws, with the score and text centred left to right.

## #54: feat: Where you observe - home, Back to home, Add a site (v0.6.5)

*merged 2026-09-25 · `feat/where-you-observe` → `main`*

"Where you observe", built to the mockup the owner approved (v0.6.5).

- **Settings › Where you observe** replaces "Beats".
  - One list of saved sites plus "This Mac's location". Click a row to observe from it.
  - A star marks home. Home can be a saved site or this Mac.
  - A dark site you're only visiting is listed apart, with Keep and Back to <home>.
  - "Add a site…" opens a sheet with labelled Name, Latitude and Longitude fields, "Use this Mac's location", and sky darkness chosen by name (Bortle 1 Pristine to 9 Inner city). It rejects 0, 0 and names already taken in any case.
- **"Observe from here"** on a dark-site card visits the site without saving it.
- **Back to home, one click:**
  - The popover shows "Observing away from home · Back to <home>".
  - The Dark sites heading has a "Back to <home>" link.
- **Honest comparison:** dark-site cards and the popover's "Clearer sky" line compare with home's own plan. While away, home's forecast is fetched with a 30-minute cache, after the alerts, with a 10-minute retry limit.
- **Menus instead of up/down arrows:** every numeric setting is now a menu showing its value (go rule, nudge, quiet hours, search radius, minimum clear run). This was the owner's second request.
- **Migration:** a config from before 0.6.5 that was on Automatic keeps this Mac as home. The app also looks up this Mac's location at launch, so the row is ready in Settings.
- **Removed:** `Copy.siteNoun` and `adoptAsBeat`. Docs, UAT 3, 11, 36 and 41–43 are updated. Version 0.6.5, build 17.

Checks:
- 227 tests pass, 13 of them new: home defaults, This Mac as home, visit, keep, choose, go home, remove, migration, case-insensitive names, Bortle names.
- The release build is clean.
- Live: the owner's screenshot shows the popover's "Observing away from home · Back to <home>" bar.
- Review: no Critical findings. All three Important findings are fixed:
  - "This Mac's location" was greyed out after a launch on a saved site.
  - This Mac could never be home.
  - "Clearer sky" compared against the visited site instead of home.
- The Minor findings are fixed too.
- One exception: going home still fetches a fresh main forecast rather than reusing the cached home forecast. The cached one has no Open-Meteo second opinion, and the popover's agreement line needs it.

No-issue: owner-approved sites mockup, plus the owner's Settings feedback, given in conversation.

## UAT

**UAT:** In the popover while away, click "Back to <home>" → the header changes to Home. Settings › Where you observe → star a site, then "Add a site…" and add one → it is saved and selected. Every numeric setting is a menu showing its value.

## #55: feat: aurora on the widgets, aurora alert sound, large widget fits (v0.6.6)

*merged 2026-09-25 · `feat/aurora-widget` → `main`*

Aurora on the desktop widgets, a sound for aurora alerts, and a large widget that fits its real size (v0.6.6). Built to the owner-approved mockup.

- **Widgets:**
  - Small: the second line becomes "● Aurora amber" in AuroraWatch UK's colour.
  - Medium and large: "● AURORA AMBER" at the end of the header line, at no cost in height.
  - It shows under the popover's rule: alerts on, at or above the chosen level, published within the hour. It clears on time through a timeline entry at expiry.
  - The app rewrites the widget only when the shown level changes, and every 30 minutes while it shows, to respect WidgetKit's reload budget.
- **Aurora notifications** now play the alert sound.
- **Large widget overflow:** measured at the real 344 × 344 pt size (about 312 pt of content), it needed up to 348 pt on a clear night with three targets, cutting off the footer. Tighter bars, icons and spacing bring it to at most 297 pt. The medium widget is also tightened to fit 132 pt exactly in its worst case.
- **One aurora rule:** `AuroraSettings.shows` and `isFresh` now serve the popover, widget, Store and alert engine alike, with a test pinning the widget refresh inside the freshness window. This came from the review.
- Version 0.6.6, build 18. Product overview and UAT 36 and 44–46 updated.

Checks:
- 229 tests pass, 2 new. The release build shows no warnings.
- Widget layouts measured with NSHostingView at the real sizes, with a red aurora showing: small 131/132, medium ≤132/132, large ≤297/312.
- Not seen live: tonight's AuroraWatch status is green.
- Review: no Critical findings. The Important finding (the duplicated rule) is fixed, and so are both Minor ones.

No-issue: owner-approved aurora mockup, given in conversation.

## UAT

**UAT:** With aurora alerts on, when AuroraWatch UK reaches your level after dark → the widgets show "● Aurora <level>" in AuroraWatch's colour, and the notification plays a sound. On a clear night the large widget's footer is fully visible.

## #56: feat: signed, notarised download tooling; data-licence credits

*merged 2026-09-25 · `feat/release-prep` → `main`*

Getting ready for public download (part of 0.6.6): release tooling, plus the licence changes found while checking the data sources' terms.

- **`scripts/release.sh`** builds a Developer ID signed, notarised and stapled `Nightwatch-<version>.dmg`, and verifies it with `spctl`. `--publish` attaches the DMG and its SHA-256 to the GitHub release for the tag. The one-off setup and each release are in `docs/releasing.md`, and the README gains a Download section.
  - The widget needs no provisioning profile. Only the app does, for WeatherKit.
  - `--publish` refuses unless HEAD is the tagged commit and nothing is uncommitted.
  - The team ID is read from the certificate itself.
- **`build-app.sh`:**
  - It uses development profiles only, so an installed Developer ID profile can't break everyday builds.
  - It passes the app's version to the widget. The widget had been reporting a literal "1.0" from xcodegen.
- **AuroraWatch UK:** the popover's aurora line and the About window link to their site, as their API terms ask. Every request now names the real app version in the User-Agent (it said "0.1").
- **Sky-survey images:** credited exactly as CDS's ODbL 1.0 licence and STScI's non-profit terms ask, in NOTICE, About, README, the product overview, and on each detail page that shows one.

Checks:
- 229 tests pass.
- `scripts/release.sh --skip-notarize` run with the development certificate:
  - Both bundles were re-signed widget-first, with hardened runtime and timestamps.
  - `codesign --verify --deep --strict` passes.
  - The DMG contains the app and the Applications shortcut.
  - The widget's App Group is `8B44CZ9923.…`, and the widget reports 0.6.6 build 18.
- Without a Developer ID the script stops at step 1 with a pointer to the docs.
- Not yet run: notarisation, stapling and `--publish`, which need the owner's Developer ID certificate and notary credentials.
- Review: both Important findings are fixed (the team ID, and publishing from the tagged commit), and so are all four Minor ones.

No-issue: owner request to distribute via website and GitHub releases, and to honour the data licences.

## UAT

**UAT:** After the setup in docs/releasing.md, tag v0.6.6 and run `scripts/release.sh --publish` → it ends "accepted source=Notarized Developer ID", and the GitHub release has Nightwatch-0.6.6.dmg, which opens on another Mac without a warning.

## #57: docs: copy the Developer ID profile where the release script looks

*merged 2026-09-25 · `docs/releasing-profile` → `main`*

`docs/releasing.md` step 2 now says to copy the Developer ID profile into `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile`, with a one-line command.

This came up during the owner's first setup. Double-clicking the downloaded profile installs it under System Settings › General › Device Management instead, where `scripts/release.sh` can't read it.

Checks: the owner's profile, copied this way, is found by the script's own search. It is Developer ID (`ProvisionsAllDevices`), has WeatherKit, and has App ID `8B44CZ9923.io.github.rsutcliffe.nightwatch`.

No-issue: found during the owner's first release setup.

## UAT

**UAT:** Follow docs/releasing.md step 2 on a fresh setup → `scripts/release.sh` finds the profile, with no "no Developer ID provisioning profile" error.

## #58: docs: product overview up to 0.6.6, the first public download

*merged 2026-09-25 · `docs/overview-0.6.6` → `main`*

Brings `docs/product-overview.md` up to v0.6.6, the first public download. Every change was checked against the code.

- **Opening and install:** the signed, notarised download from GitHub comes first. Building from source is second.
- **Popover:** the "Observing away from home · Back to <home>" bar, and the aurora line linking to AuroraWatch UK.
- **Targets:** constellation artwork on the cards, and the survey-image credit on detail pages.
- **Widgets:** included in the download.
- **Settings:** every numeric setting is a menu.
- **Data sources:** the non-commercial terms shared by Open-Meteo, 7Timer, AuroraWatch UK and the DSS, why Nightwatch is therefore free, and that 7Timer's author has been told.
- **Architecture:** NightwatchUI, the widget's xcodegen project and App Group snapshot, and `scripts/release.sh` (see `docs/releasing.md`).
- **Tone:** the owner's rule that flavour stays out of anything a newcomer must act on.
- **What it is not:** not commercial, and not on the Mac App Store, because the app isn't sandboxed.
- **Release history:** the 0.6.6 row notes the first public download.

Checks: NightwatchUI is imported by both the widget and the popover. "Hold fire" is the Watch-mode wording ("Less certain" in plain mode). "Observe from here" and "Where you observe" appear in the code as stated.

No-issue: owner request to update the product overview.

## UAT

**UAT:** Read docs/product-overview.md on GitHub → the Install section starts with the download link, and the 0.6.6 row says it was the first public download.

## #59: privacy: remove the owner's home location from code, tests and docs

*merged 2026-09-25 · `privacy/remove-home-location` → `main`*

Removes the owner's home location from every tracked file, at the owner's request: the town name, its region, and the precise latitude and longitude that the tests used.

- **Tests:** a made-up "Test site" at 54.0° N, 1.5° W, a round point in open country, replaces the home coordinates in every test file. Test names and comments are renamed to match. All 229 tests pass unchanged apart from two aurora title strings, so none depended on the exact spot.
- **Code comments:** "a site at 54° N" or "Home".
- **Docs:** the product overview, specs and plans say "Home" or use `<home>` as a placeholder. The "built for…" line no longer names a place.
- **Checks:** `git grep -i` for the town name finds nothing, and neither the old coordinates nor nearby rounded forms appear anywhere. The two tracked images carry no GPS metadata.

Not covered here: earlier commits, commit messages and pull-request descriptions still contain the location. That needs a separate decision from the owner.

No-issue: owner privacy request.

## UAT

**UAT:** On GitHub, search the repository for the town name → no results in the code or docs on main.

## #60: fix: Targets page repaints on sidebar clicks; constellations' Moon separation

*merged 2026-09-25 · `fix/constellation-moon-sep` → `main`*

Two bugs found while taking website screenshots.

- **The Targets window stopped repainting.** The sidebar set `ui.section` and `ui.selected` from inside a SwiftUI view update. The log showed "Publishing changes from within view updates is not allowed, this will cause undefined behavior" on every click. Afterwards the detail pane kept showing an old page while clicks landed on the real, invisible one. The owner reported it as "the whole hitbox is messed up". The selection is now applied just after the update.
- **"Moon sep. 0°" on constellation pages.** Constellations were given a placeholder 0. They now carry the Moon's distance from the constellation's centre, and are still never counted as Moon-washed. The Moon's own page shows "Illuminated" instead of a separation.

Checks:
- 230 tests pass, 1 new (`constellationsCarryTheirMoonSeparation`). The release build is clean.
- Live: no "Publishing changes" warning in the app's log since the fix went in at 17:01, through the owner's clicking round the sidebar, which they confirmed now works. Before the fix: 14 warnings between 16:57 and 16:59.
- Live: the Cygnus page shows "Moon sep. 64°" and Cassiopeia "56°". Links to NGC 7000, Cassiopeia and M31 each land on the right page.

No-issue: found by the owner during screenshots.

## UAT

**UAT:** Targets → click every sidebar group, open cards, go back and switch again → the page always matches the highlighted group. Open Cygnus → Moon sep. is a real angle, not 0°.

