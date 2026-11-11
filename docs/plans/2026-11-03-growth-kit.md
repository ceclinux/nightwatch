# Growth kit for the 1.0.1 / 1.7.2 release (3 November 2026)

What is ready, what each item still needs, and the exact steps. Nothing here has been entered in App Store Connect except what the plan
records as done. Items follow `docs/plans/2026-11-03-release-1.0.1-and-1.7.2.md`, section 4.

## 1. Screenshots (recapture in the moonless week, 6 to 12 November)

New Moon is Monday 9 November in the app's own calendar. Capture at the public demo site (Malham Tarn), never home. Target: up to 10 per platform, one
story across the first three (promise, proof, payoff).

| # | iPhone and iPad | Mac |
|---|---|---|
| 1 | Tonight: sky score and clear window | Popover: sky score and clear window |
| 2 | Targets with colour pictures and "how to shoot this" | Targets window with colour pictures |
| 3 | Home Screen widgets and the Lock Screen card | Widgets |
| 4 | Tonight's plan | Tonight's plan |
| 5 | Your horizon dial (`-demoOpen horizon`) | Your horizon (`docs/images/screenshot-horizon.png` is the README's) |
| 6 | Aurora and dark skies (`-demoTab sites` on iPad) | Dark sites |
| 7 | The week ahead (`-demoTab week`) | Week ahead |
| 8 | Red night mode (Settings > Display) | (none: the Mac has no red mode) |

Sizes (App Store Connect takes these; checked with `asset_check.py` before upload): iPhone 6.9-inch 1320 x 2868 (the medium-display tab takes the 6.3-inch
sizes; 1320 x 2868 was rejected there on 27 October), iPad 13-inch 2064 x 2752, Mac 2880 x 1800. Captions: 12 words at most, no price, no URL, no
Apple recognition. The iOS 27 Simulator is unreliable (SpringBoard crash): capture on the owner's devices, or with the demo launch flags where they behave.
Run `xcrun simctl shutdown all` afterwards. Needs the owner's devices and a clear evening, so this item is the owner's with my help on the framing and the check.

## 2. In-app event: "Moonless week" (iPhone and iPad only)

Draft copy, linted (`release-1.0.1/event-copy.json`): name **Moonless week** (13 of 30), short **Dark nights ahead: plan your imaging session** (44 of 50),
long **The darkest skies of the month: Nightwatch finds your clear window and the targets that suit your telescope.** (108 of 120). Badge: **Special Event**.
No price anywhere. Dates (provisional, to be matched to the app's own Moonless run for December before submitting): **6 to 12 December 2026**; the new Moon
that month falls on 9 or 10 December (mean-lunation calculation, cross-checked: it gives 9 November, as the app does). Submit by about 14 November so
approval lands before the 14-day promotion window.

Art, made from the owner's night-sky backdrop with `creative_assets.py` and passing `asset_check.py`: `build/event-art/appstore-event16.jpg` (3840 x 2160, the
card) and `appstore-event9.jpg` (2160 x 3840, the details). Regenerate with:

```bash
cd /Users/richardsutcliffe/Code/Astronomy
python3 <skill>/scripts/creative_assets.py --art Resources/Backdrop/night-sky-wide.jpg --outdir build/event-art --caption "Moonless week" --which event16,event9 --focus 0.5,0.5
```

**Created in App Store Connect on 3 November as a draft (event id 6830272647, "Moonless week December 2026"); not submitted.** Fields: Special Event badge, normal
priority, no in-app purchase needed, purpose "Appropriate for all users", all countries, event 6 Dec 2026 00:00 to 13 Dec 2026 00:00 GMT, publish start
22 Nov 2026 (the 14-day promotion window). Both images attached and read back after a reload. Quirk: a second upload through the same file input did not register
and the first details image showed "Your file is in the wrong format" while still processing; removing it and uploading a copy under a new file name worked.
Event URL: https://apps.apple.com/us/app/id6816390602?eventid=6830272647. Before **Add for Review**: match the dates to the app's own December Moonless run (the
new Moon is on 9 or 10 December by a mean-lunation calculation, which gives 9 November, as the app does), and submit by about 14 November. Attach it to the
featuring nomination once approved. Only the owner presses Add for Review.

## 3. Custom product pages and campaign links

Pages need Ready for Distribution (true) and Apple approval; up to 70; keywords come from the latest approved version and a keyword combination can
belong to one page only. URLs are copied from App Store Connect, never built. Two to start (see the matrix in the plan). Their screenshots come from the
recapture in item 1: build the pages after it.

Campaign links need the owner's **provider token (pt)** from App Store Connect > Analytics > Campaigns, which I do not guess. Once given, one command:

```bash
python3 <skill>/scripts/campaign_links.py --base "https://apps.apple.com/gb/app/nightwatch-clear-sky-alerts/id6816390602" --provider <PT> --app nightwatch --channel readme --out build/campaigns.json --csv build/campaigns.csv
```

(repeat with `--channel website`, `forum`, `horizon`), then `make_qr.py --registry build/campaigns.json` for any printed use. Test a custom-page URL combined with
the tokens before relying on it (Apple's pages do not confirm that combination).

## 4. Website (separate repository)

Handover: `docs/plans/2026-11-01-website-handover-iphone-ipad.md`. State of https://delphi-dolphin.com/nightwatch on 3 November: no Smart App Banner, the
text still says "Mac only", iPhone is not mentioned. It is the website session's job; paste the handover there.

## 5. After approval

`python3 scripts/verify-survey-pack.py` downloads the published pack and checks it as the app reads it (3 November: 18,351,465 bytes, sha256 starting
a4cdcc8c, 1,948 entries, every one a readable 480 x 274 picture, and the app's key for all 1,948 listed targets finds one). After Apple approves 1.7.2 and 1.0.1:
1. `swift scripts/review-status.swift` shows READY_FOR_DISTRIBUTION for both; the iTunes lookup shows 1.0.1.
2. On a device or a Mac with the app's caches folder empty, open Targets: cards show colour pictures, with one download of `survey-set.nwsp` and no request to CDS.
3. Check `Caches/Nightwatch/survey-set.nwsp` exists (about 18 MB) and `thumbs/` fills.
