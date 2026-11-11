# Handover for the Nightwatch Mac project: apply the "Photographic" design language

> **Status, 26 October 2026:** applied. The Mac app took this design language in 1.7.0 (live in the App Store since 26 October 2026). The file is kept as the design reference. Its paths into `~/Code/NightwatchPhone` are out of date: that repository is only an archive now, and the phone code is under `Phone/` in this repository.

Written 18 October 2026 from the phone project's session. The owner has now asked for the Mac app to take the design language the iPad and
iPhone apps adopted today. Nothing here has been applied to `~/Code/Astronomy`. Apply it in the Mac project's own session. The phone code is
the working reference: `~/Code/NightwatchPhone` on `main` (commit a5c1c62), mainly `Sources/PhoneUI`, `Sources/PhoneWidgetUI` and `docs/brand.md`.

The Mac's tokens, popover and widgets were the source of the phone's original look; the phone diverged on 18 October 2026 by the owner's decision,
and the owner now wants the Mac to follow. Red night mode is unchanged in spirit: one hue on black, the picture tinted red.

## What the look is, in one paragraph

A full-bleed night-sky picture behind everything, under a dark scrim. No heavy boxes: text sits straight on the picture where it can, and
cards are faint glass (a barely-there white fill and a hairline). One typeface (SF Pro) used in two contrasting weights: heavy for names and
values, thin for the large times, small wide-tracked capitals for labels. Warm white for what is lit, one amber accent used very sparingly
(the call-to-action pill, the "now" marker, a heart), and a quiet outlined chip for every warning. The Mac's signature 60-tick dial stays,
with a bold score inside.

## Tokens (all in `Theme.swift`; Mac equivalents go in `Tokens.swift`)

| Token | Normal | Red mode | Use |
|---|---|---|---|
| lit | `#F4F1EA` | `#FF2A1A` | what is lit: clear hours on the arc, lit dial ticks, the hours line, a target's best time, links, selected tab |
| accent | `#F4F1EA` (was system blue) | `#FF2A1A` | the old accent, now warm white. Switch tracks are lit with a dark knob; a selected segment is a warm-white pill with dark text |
| ember | `#E8A04A` | `#FF2A1A` | the ONE call to action on a screen, the "now" dot on the arc, a favourite heart, a map pin. A flat colour, never a glow |
| warning | `#E8A04A` (was yellow `#EDB40D`) | `#FF2A1A` | the outline and tint of the warning chip only |
| glassFill | white 9 % | `#A0140C` 10 % | cards over the picture |
| glassHairline | white 16 % (text colour under Increase Contrast) | `#A0140C` 35 % | card outline |
| background | `#14171D` | `#000000` | unchanged |

Scrim over the picture (background colour at these opacities, top to foot): Tonight 16 % to 78 %; every list or form screen ("calm") 55 % to 88 %;
at accessibility text sizes 88 % to 92 %, so text never depends on the picture. Red mode: the picture is desaturated and multiplied by `#C0180E`.

## Shared pieces to build once (so a change is one edit)

- **`cardSurface()` / `Card`**: 16 pt radius, glass fill and hairline. Solid card instead under Reduce Transparency and at accessibility text sizes.
  No screen draws its own card background.
- **`capsLabel()`**: small, semibold, 1.4 tracking, capitals, supporting colour. All section labels ("BEST TONIGHT", Settings headers).
- **`WarningChip`**: a warning triangle plus words in a capsule with a 1 pt amber outline and a faint amber fill, text in `lit`. Used for the high dew risk,
  forecasts disagreeing, and a plan clash (see below). **Never** a "!" in the text and never coloured bold type: the owner rejected both twice.
- **`PillButton`**: ember capsule, heavy dark text, 44+ pt tall.
- **`TwoWeight.headline`**: the headline with everything heavy except the last word, which is thin ("**Clear window** tonight"). Source: `PhoneWidgetUI/NightArcCanvas.swift`.
- **`NightArcCanvas`**: the night as a low arc, in `PhoneWidgetUI/NightArcCanvas.swift`, shared by the app and the widget (parameters for colours, labels, glow).
- **`TonightHero` + `TonightHero.Fact`** (`PhoneCore/TonightHero.swift`, tested): pure text logic that splits SkyCore's window string into times and hours,
  words the dew line, drops a "Dark" fact that repeats the window and a reason that repeats the dew line, and joins the Moon note. It contains no new wording
  beyond joining. Consider moving it to SkyCore so both apps share it.

## Type rules (one typeface, SF Pro)

- Names, titles and values: heavy. Examples: target names (title2 heavy), day names, site names, fact values (title3 heavy), list titles on Targets.
- Large times and the clear window: thin (30 to 38 pt). Headline: heavy, last word thin.
- Descriptors ("EMISSION NEBULA", "CONSTELLATION"): caption2, 1.2 to 1.4 tracking, capitals, supporting colour.
- Running text: regular. The score numeral inside the dial: bold.
- No serif, no gold gradient, no glow on type (all tried and rejected by the owner).

## Tonight (the popover on the Mac)

In order: overline ("TONIGHT · MALHAM TARN" and the date line); the dial with a bold score beside the verdict (headline, thin times, the hours line,
the dew chip if the dew risk is high or frost is likely, the reason line unless it repeats the dew line, the agreement line: a plain tick line when forecasts agree,
a `WarningChip` when they disagree); the night arc; the facts; then the three best targets; the alerts pill; the footer.

- **Dial**: the existing 60-tick, 12-hour bezel, lit ticks in `lit` with one glow. The score is bold.
- **Arc** replaces the ten bars on Tonight only: each hour a stretch of the curve, lit with a glow where the sky is clear (brighter the clearer),
  a faint line where it is not, and the hour under its stretch (bold and bright when clear, faint when not). An ember dot marks the current hour when it falls in the night.
  The Moon note ("Moon 53% · Sets 22:57") sits under it.
- **The Week page keeps its bar charts** (owner, 18 October: multiple arcs would not work there). The arc is Tonight's alone.
- **Facts** (Seeing, Wind, Transparency, and Dark only when it differs from the window): a small capital label over a heavy value, in a grid. All values the same size, never truncated mid-word.
  Two columns on a narrow surface, a single row when wide, one column at accessibility sizes.
- **Best tonight cards**: the picture runs to the card's edges with a dark gradient foot; name heavy, type in tracked capitals, best time in `lit`. Brighten and lift the contrast of
  survey cutouts slightly so near-empty fields still show. Solid card, picture above the words, at accessibility sizes.
- **Alerts card** (until alerts are decided): a glass card with the ember pill.
- Offline and failure notes keep their dashed amber outline.

## The other screens

- **Plan**: each row is a glass card: the best time (heavy), a line sample, the target ID (headline heavy), the type in tracked capitals, "Best 23:32 at 55°".
  A clash is a short `WarningChip` reading **Clash** with "Same best time as NGC 1491, Uranus" as plain secondary text beside it. A long chip that leaves empty space was rejected.
  Segmented "Tonight / Tomorrow night" switch: selected segment a warm-white pill with dark heavy text.
- **Targets list** and group pages: glass rows, titles heavy, counts semibold, icons in `lit`, a favourite heart in ember when on.
- **Week**: glass cards, day name heavy, the existing bars (lit hours in `lit` with a glow), verdict bold.
- **Events, Dark sites, Sites, Settings**: glass cards, heavy names, `capsLabel` section headers, switches as above, the same calm scrim. The primary action on a card
  ("Observe from here") is ember.
- **Backdrop** on every screen via one `StarField`-style view; Settings and Sites sit on it too. Do not draw a second crop of the picture beside another (the iPad sidebar
  briefly did, and it looked disjointed; it is plain dark now).

## Assets

- `night-sky-wide.jpg` (2400 px wide, landscape) and `night-sky-tall.jpg` (1400 x 2100, portrait) in the phone's `App/Resources/Backdrop`, cut from the owner's images. The Mac can use the same files;
  a wide window wants the wide one. The originals are in the owner's `~/Downloads/Archive 2.zip` (4128 x 2304). The owner has said where the images came from; the source line for credits
  is theirs to give, so check with them before anything ships and add any credit to the README.
- Keep the earlier Unsplash Milky Way photograph (William Zhang, credited in the README) as the fallback when the new files are missing.

## Accessibility (all of it was kept working on the phone; keep it on the Mac)

Red night mode, Increase Contrast (glass hairline becomes the text colour, supporting text brightens), Reduce Transparency (glass cards become solid and the picture is dropped),
Dynamic Type or the Mac's text size (cards go solid and the scrim near-opaque at the largest sizes), VoiceOver (the dial reads as one label; the arc reads the hour-by-hour percentages and the Moon note; a warning chip reads as one element),
Reduce Motion (the arc and the score do not animate in; the twinkle is off).

## The home-screen widget (Mac desktop widget)

The phone's widget now matches: dial with a bold score and glowing lit ticks, the two-weight headline, thin times, the glowing arc (medium and large) with hour labels (large), target rows with heavy IDs
and tracked capitals, and the night-sky picture behind everything under a scrim (40 % to 78 % black; plain black in red mode). Lessons from getting it onto real devices, all of which cost hours:

1. **Keep the widget's background picture small.** A 900 px picture (about 125 KB) in the widget's asset catalogue made **every newly added widget stay a grey skeleton forever**, with no crash report. At 360 px
   (13 KB) they load. Widgets have a small memory budget. Put the picture in the widget's `Assets.xcassets` and use `Image("name")`; a bare file loaded with `UIImage(named:)` was not found.
2. A widget shows a drawn snapshot until its timeline reloads, so after installing a build open the app so it asks for a reload, or remove and re-add the widget.
3. If the project is generated with xcodegen, it writes `CFBundleVersion` into the Info.plist as a literal `1`; set it explicitly in `project.yml` for the app and the widget if iOS or macOS seems to keep an old extension.
4. The large widget has far less height on an iPad than an iPhone; use `ViewThatFits(in: .vertical)` with a full and a shorter layout so nothing is ever clipped. Vertically centre the content, leading-aligned.
5. On the iPad the extra-large size never loaded at any layout tried (even a plain text one), probably for the same memory reason, and was removed. Check it on the Mac before shipping that size.
6. Render widgets with no blur layers where you can; the arc's glow and the dial's glow are drawn once each.

## Constraints that apply to the Mac too

- Plain hyphens only (no en or em dashes) in anything shown; the Mac's SkyCore wording uses en dashes in time ranges, so apply `String.plainDashes` before display, as the phone does.
- No mention of how the app or its pictures were produced, anywhere in app text, docs, commits, PRs or store copy.
- The tests that guard wording and logic stay green; add a test with each pure logic piece you move or write (the phone's `TonightHeroTests` is the model).
- Verify in a real window at several sizes, in red mode, with Reduce Transparency, Increase Contrast and the largest text size, then on the desktop widget. Shut any Simulator or test app down afterwards.

## Decisions the owner has already made (do not reopen)

- Warm white and amber only; the gold tone, the glow on type, the serif numeral and the system blue accent were all tried and rejected.
- The dial stays; the bar chart is replaced by the arc on Tonight, and kept on the Week page.
- Warnings are chips with an icon, never a "!" in text.
- One typeface in contrasting weights.
- Each device keeps its own chosen site (the existing per-Mac rule); Home syncs. This handover does not change that.
