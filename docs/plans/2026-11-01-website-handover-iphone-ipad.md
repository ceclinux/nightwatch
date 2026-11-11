# Website handover: Nightwatch is now on iPhone and iPad (for the delphi-dolphin.com session)

Apple approved the iPhone and iPad app (iOS 1.0) and it is live; checked 1 November 2026 against the public App Store record
(id6816390602, free, iOS 17.0 or later, 5 iPhone and 5 iPad screenshots). It is the same listing and the same free purchase as the
Mac app: **Nightwatch: Clear Sky Alerts**, https://apps.apple.com/gb/app/nightwatch-clear-sky-alerts/id6816390602

Apply in the website's own repository; this session does not touch it.

## What the page says now (https://delphi-dolphin.com/nightwatch) and the change

| Where | Today | Change to |
|---|---|---|
| Page title | "...astrophotography targets for Mac" | "...for Mac, iPhone and iPad" |
| Header tagline | "Mac menu-bar app" | "Mac menu-bar app, iPhone and iPad" |
| Top and closing button | "Download on the Mac App Store" | "Download on the App Store" (same link) |
| Requirements line | "Mac App Store 17.8 MB, or disk image 24 MB · macOS 14 or later, Apple silicon" | add "iPhone and iPad: iOS 17 or later, same free purchase" (take the iPhone size from the App Store page, not from this note) |
| Availability note | "Mac only. Open this page on your Mac to get it, or email yourself the link." | remove "Mac only"; say it works on Mac, iPhone and iPad and that the App Store link opens the right one on each device |
| Install step 1 | "Get it from the Mac App Store, then open it from the menu bar." | keep for the Mac; add one line: on iPhone or iPad, open the App Store link and tap Get |
| Footer trademark | lists "App Store and Mac App Store" | no change |

Sections about the menu bar, Siri on the Mac, "Your Macs, in step" and the disk image stay Mac-specific and need no change.

## Facts to state, and not to overstate
- One free purchase covers Mac, iPhone and iPad. No ads, no in-app purchases.
- The phone app tells you whether tonight is worth setting up the telescope, sends the clear-sky alerts, and has Home Screen and Lock Screen widgets; the
  README in `Phone/README.md` has the feature list.
- Do not mention how the app was built. No AI-tooling wording anywhere (standing rule).
- Screenshots: the iPhone and iPad ones are in App Store Connect and on the listing; the website can reuse the listing's images.

## Add for discovery (Apple's own web features)
- **Smart App Banner:** in the `<head>` of the Nightwatch page (and any page that mentions the app): `<meta name="apple-itunes-app" content="app-id=6816390602">`.
  Apple's behaviour: it opens the app if it is installed, otherwise the App Store listing, and is hidden on devices or in regions that cannot use the app.
- **Tagged App Store link** so we can see what the site sends: use this one for every App Store button and the badge on the site (made in App Store Connect's
  campaign links, 6 November 2026; the provider token is not a secret, it is in every tagged link):
  `https://apps.apple.com/gb/app/nightwatch-clear-sky-alerts/id6816390602?pt=1028621&ct=nightwatch-website&mt=8`
  Apple reports a campaign only once five different accounts have installed through it, so App Store Connect (Analytics > Campaigns) will stay empty for a while.
- **Badge:** use Apple's "Download on the App Store" badge as Apple's marketing guidelines require (size, clear space, one badge per layout), not a text lookalike.

## Verify
Open https://delphi-dolphin.com/nightwatch after deploy → the button reads "Download on the App Store" and goes to the listing above, "Mac only" is gone, and the page names iPhone and iPad.
