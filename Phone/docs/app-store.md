# App Store submission notes (draft)

The Mac app (1.7.0) is approved and live. The iPhone and iPad version is a second platform on the same App Store record (6816390602), added on 27 October 2026 without waiting for Apple case 103007210525. Its listing text, screenshots and review notes are entered; the build is attached and Add for Review is pressed only by the owner (28 October 2026: iPhone and iPad 1.0.0 build 6, the Mac 1.7.1 build 51 as its own later submission).

## App Review notes (write these first, not after a rejection)

App Store Connect holds a condensed form of the notes below (3,456 of 4,000 characters, read from the page on 28 October 2026): the same facts, shortened, with an opening line saying this version joins the Mac app's record and bundle ID (universal purchase), and a closing line on how to see the app working. The longer wording here is the reference; change both together.

Nightwatch tells you whether tonight is worth observing the night sky, and alerts you. No account or sign-in is needed.

- **Apple Weather attribution.** Apple Weather's mark and its legal-attribution link are shown in the footer of the Tonight
  screen whenever Apple Weather supplied the forecast, and are kept on the device so they show without a connection. When
  Apple Weather is not the source, its mark is not shown and the footer names the service that is (Open-Meteo).
- **Location** is requested only when "Use this device's location" is pressed on the welcome screen. A place name can be
  typed instead.
- **Notifications** are requested after Tonight's answer has been shown and a card has explained the alerts; the system
  prompt appears only when "Turn on alerts" is pressed.
- **Background refresh** is used to read a fresh forecast and re-queue the alerts. iOS decides when it runs.
- **iCloud key-value storage** shares saved sites and alert settings with the developer's Mac app (the same identifier).
- **Red night mode** is a display palette for use at a telescope.
- **Maps and Apple Maps search** find a place when one is typed, suggest car parks and towns for the dark sites list, and draw a
  small map of each dark site.
- **Home-screen widgets** (small, medium and large) show tonight's answer. The app and the widget share it through an App Group
  (`group.io.github.rsutcliffe.nightwatch.phone`); the widget fetches nothing. When Apple Weather supplied the forecast, Apple's mark is on
  the small, medium and large widgets and on the Shortcuts answer cards (the app keeps the image in the App Group, as the Mac does); the mark
  links to Apple's legal page except on the small widget. Otherwise the service's name is shown.
- **Forecast sources** are tried in order: Apple Weather, Open-Meteo, MET Norway, 7Timer. The footer on Tonight names the one that answered, and the
  Apple Weather mark is shown only when Apple Weather did.
- **Shortcuts and Spotlight** (App Intents) read the forecast the app already holds; only Refresh fetches. On iOS 27 Siri's "find X in Nightwatch" goes to the app's in-app search (a target page's group, with the search words in its box); questions about tonight open the plan. A spoken tonight question is still answered by Siri from its own sources. The `nightwatch://` link scheme opens a target or the
  plan from the widget and from Shortcuts.
- **Aurora alerts** are off by default. When on, the app reads AuroraWatch UK's status (UK and Ireland) or NOAA's aurora forecast (elsewhere)
  while it is open and when iOS grants a background refresh, and posts a local notification. No server is involved.
- **Photos:** "Measure from a photo" (in a site's Horizon) uses the system photo picker, so no photo-library permission is
  requested. The chosen photo is read on the device and not kept.
- **Lock Screen card.** When a clear window opens, the app starts a Live Activity (a local ActivityKit card; no push service and no server) with the sky score and a
  countdown to the end of the window, and the system marks it over when the window closes. It is switched off with Settings › "Clear-window card on the Lock Screen".
- **Siri search (iOS 27).** "Find the Crescent Nebula in Nightwatch" runs the app's in-app search (`.system.searchInApp`) and opens the Targets group of the best
  match; words that ask for tonight open the plan. The app does not claim to answer other spoken questions: Siri answers those itself.
- **Devices tested.** iPhone 15 Pro, iPad Air (M3) and the Simulator, including the simulated iPhone Duo (inner display). It was not tested on a physical iPhone
  Duo; a report from an owner is welcome.
- **Entitlements and capabilities in the build:** WeatherKit; iCloud key-value storage (`$(TeamIdentifierPrefix)io.github.rsutcliffe.nightwatch`); one App Group
  (`group.io.github.rsutcliffe.nightwatch.phone`, shared with the widget); location when in use; local notifications; Live Activities; background fetch (a
  best-effort forecast refresh). The same bundle ID, name and record as the Mac app (universal purchase).
- **To see the app working:** open it, choose any place on the welcome screen, and Tonight's answer appears.

## App Privacy answers

The record is one for all platforms, so there is one set of App Privacy answers and the Mac's already stand
(`docs/app-store.md`, "App privacy answers"): nothing changes in App Store Connect when the iOS version is added, but check
that the page still shows them before submitting.

- **Data types:** Location › **Precise Location** (the forecast services receive a saved site's coordinates, to four decimal places).
- **Purpose:** App Functionality only. **Linked to the user:** No. **Used for tracking:** No.
- Nothing else is collected. What the iPhone and iPad app adds is not collection by the developer: iCloud key-value storage and Apple Maps
  (typed place names, car parks, small maps) are Apple's services, and the aurora, comet, space-station, sky-picture and Moon downloads carry no location.
- **Privacy policy URL:** the same `PRIVACY.md` as the Mac app, which now covers the iPhone and iPad (the record has one URL).
- **Privacy manifests:** `Phone/App/PrivacyInfo.xcprivacy` (the app) and `Phone/Widget/PrivacyInfo.xcprivacy` (the widget), checked against the code
  by `PrivacyManifestTests`. iOS asks for these, with a reason for each of certain system APIs: user defaults (own, `CA92.1`; the App Group's, `1C8F.1`) and
  file timestamps (own container or group, `C617.1`). Change a manifest and the answers above together.

## Signing and upload

The app and widget use the Mac's bundle IDs, so a signed build made with `-allowProvisioningUpdates` can add a capability to the Mac's App ID and invalidate
the Mac's profiles (it did on 26 October 2026). Use `Phone/scripts/appstore.sh`, which never lets Xcode touch the account.

1. **One-off, in the developer portal:** Profiles › **+** › **App Store Connect** (iOS) › the App ID `io.github.rsutcliffe.nightwatch` › the Apple Distribution
   certificate › name it "Nightwatch iOS App Store"; then the same for `io.github.rsutcliffe.nightwatch.widget`, named "Nightwatch Widget iOS App Store". Creating a profile
   changes no App ID. Download both and copy each to `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<uuid>.mobileprovision` (the UUID is inside the profile).
   Record the App ID's capabilities and the Mac profiles' status before and after: nothing should change.
2. `Phone/scripts/appstore.sh --check` confirms the certificate and both profiles; without `--check` it archives, exports, and checks the entitlements, the privacy
   manifests, the version and build, the encryption flag and quarantine, then writes `build/appstore-ios/Nightwatch-<version>-<build>.ipa`.
3. `open -a Transporter build/appstore-ios/Nightwatch-<version>-<build>.ipa` and **Deliver**. A build that fails processing does not use up its build number.
4. Every upload needs a build number above the last (`CURRENT_PROJECT_VERSION` in `Phone/project.yml`, in two places with the widget's `CFBundleVersion`).

## Listing text (iPhone and iPad version page)

Subtitle, category, price, age rating, privacy policy URL and App Privacy are the record's and are already set for the Mac. This version's own fields, written to the
same rules (no Pratchett or Discworld names, 5.2.1; no web address or other marketplace in the text, 2.3.10):

- **Support URL:** https://github.com/rsutcliffe/nightwatch/discussions
- **Marketing URL:** https://delphi-dolphin.com/nightwatch
- **Copyright:** `2026 Richard Sutcliffe`
- **Keywords** (93 of 100 characters): `astronomy,astrophotography,telescope,stars,forecast,seeing,dark sky,aurora,moon,nebula,widget`
- **Promotional text** (125 of 170): Know when tonight is clear: the sky score, the clear window and the best targets for your telescope, on your iPhone and iPad.
- **What's New:** not asked for a first version.

**Description:**

> Nightwatch tells you whether tonight is worth setting up the telescope, and speaks up when it is. When tonight looks clear for long enough, it sends a
> heads-up before sunset, then a nudge just before the clear spell begins. If the forecast turns, it tells you.
>
> Open it to see a sky score, the clear window, cloud by hour, darkness, the Moon, seeing, wind, dew risk and transparency, and the best targets for your
> telescope's field of view tonight.
>
> • Two forecasts compared: Apple Weather, with Open-Meteo as a second opinion, and 7Timer for seeing
> • Targets chosen for your telescope, with "How to shoot this" on every target: filter, exposure and frames
> • Tonight's plan: your favourites in the order of their best time
> • Darker skies nearby, scored for tonight
> • Your own horizon: mark what blocks your sky, or measure it from a photo
> • Aurora alerts for your site, wherever you observe from
> • Tonight's events: the Moon passing in front of a star, comets and the space station
> • Small, medium and large Home Screen widgets, and a Lock Screen card when a clear window opens
> • Spotlight and Shortcuts actions, and on iOS 27 Siri search for any target
> • A red night mode that keeps your eyes dark-adapted
> • Shares your sites and settings with the Nightwatch Mac app through iCloud
>
> No accounts, no advertising and no tracking. Nightwatch is open source.

Check every line against the build before pasting (Siri search needs iOS 27; the Lock Screen card needs Live Activities switched on).

## Before pressing Submit

- The Notes above are current and list every entitlement the build carries (the `appstore.sh` check prints them).
- A screen recording per device family is in App Review Information › **Attachment**, not only in a reply. One continuous take each, owner's hand (iPhone and iPad):
  launch and Welcome with "Use this device's location" and its system prompt; Tonight, with **the Apple Weather mark close up and its legal page opening from it (5.2.5)**;
  the footer after switching to red night mode (the mark stays white); the Targets list and a target page with "How to shoot this"; Plan; Settings, with the "Clear-window
  card on the Lock Screen" switch; the small, medium and large widgets on the Home Screen; the Lock Screen card; a Shortcuts Sky Score answer showing the mark; the photo picker
  in Horizon › Measure from a photo; and, on iOS 27, "Find the Crescent Nebula in Nightwatch" to Siri. Not on screen: the owner's home location (use a public site).
  The widgets are the same on every device now (the Mac's large layout, solid card on iOS): show the large widget on a night with no clear window too.
- After **Submit** the status reads **Waiting for Review** ("Ready for Review" means not submitted). Version Release is automatic (owner, 27 October 2026), so approval puts it on sale.

## Guideline pre-flight (27 October 2026)

The Mac's table (`docs/app-store.md`) written after the 5.2.5 rejection, rerun for the phone. For each guideline a reviewer could use to ask "where do I see this?", the answer is in the Notes AND on the recording.

| Guideline | A reviewer could ask | Evidence today | Status |
|---|---|---|---|
| 2.1 completeness | How do I use it? Any login? | No sign-in; Notes give the set-up and every entitlement; "choose any place" shows Tonight | OK; recording |
| 2.3.3, 2.3.10 metadata | Screenshots of the app in use? Other platform named? | Real captures (demo site, not the owner's home); description names no web address or other marketplace | OK |
| 2.4.1 iPad | Does it work on iPad? | Sidebar layout, tested on iPad Air; selected-row legibility fixed (PR 223) | OK |
| 2.5.4 background | Why background fetch? | Best-effort forecast refresh, re-queues alerts; named in Notes | OK |
| 2.5.11 Siri and Shortcuts | Do the actions fit the app? | Actions about the forecast and targets; Siri search for targets; the Notes say spoken answers are Siri's | OK; show one on the recording |
| 2.5.16 widgets, Live Activities | Related to the app? | Sky score widgets; the Lock Screen card is a local Live Activity with a Settings switch | OK; show both |
| 4.0 design, 4.2 minimum functionality | Is it more than a web page? | Native forecast, planner, charts, widgets, Shortcuts, red night mode | OK |
| 5.1.1(i) privacy policy | Link in metadata and in the app? | `PRIVACY.md` (PR 222 adds the iPhone section, merged at submission); in the app at the foot of Settings | OK once PR 222 is merged |
| 5.1.1(ii), (iv) consent | Asks before location? Works without? | From a button only; "add a place by name" works without it | OK; recording shows the prompt |
| 5.1.2 data sharing, privacy labels | Do the labels match? | Precise Location, app functionality, not linked, no tracking; manifests match (PR 221) | OK |
| 5.2.2 third-party services | Permission for the data? | As the Mac: Open-Meteo, 7Timer, MET Norway, NOAA, AuroraWatch UK, CDS, NASA, MPC, CelesTrak, credited in `NOTICE` and the README | OK while the app stays free with no ads |
| **5.2.5 Apple products** | **Is the Apple Weather mark and legal link shown?** | Tonight footer, widgets (small without the link) and Shortcuts cards show Apple's mark, unmodified, with the legal link; Apple's published pages require the mark and the link and say nothing about colour; the API supplies light and dark versions | OK; **recording must show it close up and open the legal page** |
| Export compliance | Encryption? | `ITSAppUsesNonExemptEncryption` false; `appstore.sh` checks it | OK |
| Privacy manifest | Required-reason APIs declared? | App and widget manifests, checked by a test and by `appstore.sh` | OK |
| Duo | Works on the foldable? | Inner display checked in the Simulator (27 October); the code uses size classes and no `UIScreen.main`; not tested on the outer display or the fold, or on a physical Duo | Stated in the Notes |

## Still to decide or provide

- Store name: none to choose. The record's name, "Nightwatch: Clear Sky Alerts", is shared by both platforms.
- App icon: the Mac app's Icon Composer file, copied to `App/Nightwatch.icon` and set to "shared" so iOS uses it (decided 13 Oct 2026). Check how it looks on the iPad home screen and in the store's 1024 size.
- Screenshots: iPhone 6.9-inch (1320 x 2868) and iPad 13-inch (2064 x 2752) sets are captured from the demo launch (site Malham Tarn, never the home), raw and framed, in the Mac checkout's `build/appstore/ios/`. Recapture on a moonless night (6 to 12 November 2026) and add a widgets image from a real Home Screen. The footer shows the words, not Apple's mark, because the demo cannot fetch it.
- App Store Connect: add the iOS platform to the record after the search case is settled, then upload with Transporter.
