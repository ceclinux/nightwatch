# Releasing Nightwatch on the Mac App Store

The App Store version, **"Nightwatch: Clear Sky Alerts"**, is built from the same code as the download. It differs in
two ways: it has no update check, because the App Store updates it (rule 2.4.5(vii)), and it has no widget helper
(1.5.4), because that works outside the sandbox and every executable in a store build must be sandboxed;
`scripts/appstore.sh` removes it. Both switches are in the one `#if APPSTORE` in `Sources/Nightwatch/Distribution.swift`,
and a test keeps it the only one. CI builds both on every pull request.

The store build also carries no temporary sandbox exceptions: those exist in the download only to copy settings from
0.6, which a new App Store user never had.

## Before you start

`scripts/appstore.sh` builds the widget through the everyday build, so it needs what `scripts/build-app.sh` needs for a
signed build with the widget: Xcode, `xcodegen` (`brew install xcodegen`), and the Apple Development certificate and
development profile already on this Mac.

## One-off setup

Everything below is at [developer.apple.com](https://developer.apple.com/account) › Certificates, Identifiers & Profiles,
or at [App Store Connect](https://appstoreconnect.apple.com), signed in as the team R Sutcliffe (8B44CZ9923). Done for
the first time on 26 September 2026; the notes in *italics* are what caught us out then.

### Step 1: a certificate request file

1. Open **Keychain Access** (Spotlight finds it; macOS keeps it in System › Library › CoreServices › Applications).
2. Menu bar › **Keychain Access › Certificate Assistant › Request a Certificate From a Certificate Authority…**
3. User Email Address: your Apple Account email. Common Name: anything (your name is fine; Apple names the certificate
   after the team, not this). CA Email Address: leave empty.
4. **Request is: Saved to disk.** *It defaults to "Emailed to the CA", which is wrong here.* **Continue**, and save it to
   the Desktop. One file serves every certificate below.

### Step 2: the certificates

For each one: Certificates › blue **+** › choose the type › **Continue** › **Choose File** (the request from step 1) ›
**Continue** › **Download** › **double-click the downloaded `.cer`**. *The double-click is what puts it in the keychain;
a certificate created on the website but not double-clicked is not installed.*

| Type (under Software) | Signs | Lasts |
|---|---|---|
| **Apple Distribution** | the App Store app | 1 year |
| **Mac Installer Distribution** | the App Store package (it appears in Keychain Access as "3rd Party Mac Developer Installer") | 1 year |

The download's own certificate is **Developer ID › Developer ID Application**. *Choose the **G2 Sub-CA** option: the
"Previous Sub-CA" expires on 1 February 2027 and takes any certificate made from it down with it.* When it is replaced,
the Developer ID profile must be edited to use the new certificate (Profiles › the Developer ID profile › **Edit**; it
takes one certificate), downloaded, and installed as in step 4. Only then delete the old certificate in Keychain Access ›
My Certificates, choosing it by its **Expires** date, since both have the same name. *Check the row carefully: the
Apple Distribution certificate sits next to it.*

### Step 3: the widget's identifier

Identifiers › blue **+** › **App IDs** › **Continue** › **App** › **Continue**. Description `Nightwatch Widget`, Bundle ID
**Explicit** `io.github.rsutcliffe.nightwatch.widget`, no capabilities ticked › **Continue** › **Register**. The app's
own identifier, `io.github.rsutcliffe.nightwatch`, already exists, with WeatherKit. The App Group the app and widget
share, `8B44CZ9923.io.github.rsutcliffe.nightwatch`, begins with the team ID, so on macOS it needs no registration.

### Step 4: two App Store profiles

Profiles › blue **+** › under Distribution **Mac App Store Connect** › **Continue** › Profile Type **Mac** (not Mac
Catalyst) › App ID › **Continue** › the **Apple Distribution** certificate › **Continue** › name › **Generate** ›
**Download**. Once for the app (`Nightwatch App Store`) and once for the widget (`Nightwatch Widget App Store`).

**Don't double-click a profile.** *It opens a System Settings "install profile" dialog, which puts it where the scripts
can't read it: press Cancel.* Instead copy each into place, named by its UUID:

    for f in ~/Downloads/Nightwatch_App_Store.provisionprofile ~/Downloads/Nightwatch_Widget_App_Store.provisionprofile; do
      u=$(security cms -D -i "$f" | plutil -extract UUID raw -)
      cp "$f" ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/"$u".provisionprofile
    done

### Step 5: the app record

App Store Connect › **Apps** › **+** › **New App**: Platforms **macOS**; Name **Nightwatch: Clear Sky Alerts**; Primary
Language **English (U.K.)**; Bundle ID `io.github.rsutcliffe.nightwatch`; SKU `nightwatch`; User Access **Full Access**
› **Create**. Check **Business** (Agreements, Tax, and Banking) shows the Free Apps agreement as active.

### Step 6: Transporter

Install Apple's free [Transporter](https://apps.apple.com/app/transporter/id1450874784) app from the Mac App Store, open it
once and sign in with the Apple Account that belongs to the team. *Until it is installed, `open -a Transporter …` fails
with "Unable to find application named 'Transporter'".*

## The first submission

**Add for Review** stays unavailable until every page below is complete. Its red "Unable to Add for Review" list names
what is missing, and each page below clears one or more of its lines. The answers themselves are under *Listing text* and
*App privacy answers* further down.

### Step 7: upload the build

1. `scripts/appstore.sh`, then `open -a Transporter build/appstore/Nightwatch-<version>.pkg` and **Deliver**.
2. Transporter shows "The app is processing", then "The app has finished processing" or an **Issue** button. The icon
   is a blank placeholder until processing finishes, which is normal.
3. *The first upload failed processing with error 91109: a file in the app carried `com.apple.quarantine`. Downloaded
   profiles are quarantined, and on macOS 27 a copy stays quarantined even with `cp -X`. `appstore.sh` now removes the
   attribute before signing and refuses to package a quarantined file.*
4. *A build that fails processing does not use up its build number: the same 1.0.0 (24) was accepted on the second
   upload.* Transporter's list is only a local history, so a failed item can stay in it.

### Step 8: App Information (sidebar › General)

- **Subtitle** and **Category**, from *Listing text*.
- **Content Rights** › **Set Up**: the app shows third-party content (forecasts from Apple Weather, Open-Meteo, 7Timer
  and AuroraWatch UK, and NASA's public-domain images) › **Yes**; you have the rights to it › **Yes**.
- **Age Ratings** › **Set Up**: None or No throughout. The result is 4+ in 172 countries, with Brazil, Korea and Vietnam
  showing their own equivalents (AL, ALL and 00+).
- Leave **App Encryption Documentation** alone: `ITSAppUsesNonExemptEncryption` is false in `Info.plist`, so nothing is
  asked about encryption.
- **Save**.

### Step 9: App Privacy (sidebar › Trust & Safety)

- **Privacy Policy** › **Edit**: the URL. *The "Privacy Policy URL" line in the red list points here, not at App
  Information.*
- **Get Started** › data is collected › **Location** › **Precise Location**. *Ticking the type is not enough: "Additional
  Setup Required" means pressing **Set Up Precise Location** and answering purpose, linked and tracking.*
- **Publish**, top right. Nothing on this page counts until it is published.

### Step 10: Pricing and Availability (sidebar › Monetization)

- **Price Schedule** › **+**: base country **United Kingdom (GBP)**, price **£0.00**, **Next**, **Next**, **Confirm**.
- **App Availability**: all countries or regions (175).
- **App Distribution Methods**: **Public**. The Apple School Manager volume-price box makes no difference to a free app.
- **Save**.

### Step 11: Digital Services Act

Business › **Agreements** › **Compliance** › Digital Services Act › **Complete Compliance Requirements** (for the whole
account; App Information › App Store Regulations & Permits overrides it per app). It is EU law and concerns only the 27
EU storefronts. Either answer keeps the app on sale there; only no answer at all gets it removed, and new submissions
ask for it.

- **Not a trader:** EU customers see a notice that EU consumer-protection rights don't apply. Nothing is published and
  nothing is verified. The usual choice for a free, non-commercial app.
- **Trader (an individual):** the address (a PO box will do), phone number and email are shown on the EU product page;
  the email and phone are confirmed with two-factor codes, and a document proving the business name and address is
  uploaded.

It is not part of review and can be changed later. *We first thought "not a trader" meant leaving the EU; Apple's own
page says otherwise.* ([Apple's guide](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements))

### Step 12: the version page, then submit

Sidebar › macOS App › **1.0.0 Prepare for Submission**. *Add for Review is only on this page.*

1. Screenshots, promotional text, description, keywords, URLs, copyright and review notes, from below. *Check the
   description against Listing text before submitting: the page still held an older copy with the GitHub address after
   this document had dropped it.*
2. **Build** › **+** › the processed build › **Done**.
3. **Save**. *Add for Review stays grey while anything is unsaved, and the red list stays on screen until the page is
   reloaded, even after the other pages are fixed.*
4. **Add for Review**, then **Submit**. The status becomes Waiting for Review, then In Review; Apple says up to 48 hours
   and emails the result. Version Release is set to automatic, so approval puts it on sale.
5. *Don't press Cancel Submission.* The text can still be edited while it waits; a different build means removing the
   version from review first.

### If App Review asks for information

*The first submission came back overnight as guideline 2.1 "Information Needed": Apple asks this of a developer account
with little review history, not because anything is wrong.* It wants a screen recording made on a real Mac running the
latest macOS, starting from launching the app, and written answers: purpose and audience, how to set up and use the app,
the external services it uses, regional differences, and any regulation or protected material.

1. Record with ⌘⇧5 › Record Entire Screen: launch from Applications, the popover, the Targets window, a target's page
   with "How to shoot this", Settings and the widget. Record in the evening, or explain the time: a morning recording
   after a cloudy night shows score 0 and empty tiles. Shrink it before attaching (the 1 min 49 s original was 240 MB):
   `ffmpeg -i in.mov -vf "scale=1920:-2,fps=30" -c:v libx264 -crf 23 -pix_fmt yuv420p -an out.mp4` gave 5 MB.
2. **Reply to App Review** with the answers and the recording attached. The box takes 4,000 characters, and *arrows,
   ellipses and "›" did not survive the paste*: use plain ASCII ("->", "...", ">").
3. Put the same information, shorter, in App Review Information › **Notes** (see *Notes for App Review*), and **Save**.
   If Apple asks how an entitlement is used, it says no new binary is needed: answer from the entitlement table there.
   *Replying alone leaves Resubmit to App Review grey (nothing was edited); Apple's message asks only for the reply.*
4. *Saving moves the version to "Ready for Review", which means added to a submission but not yet submitted.* Press
   **Resubmit to App Review** (or **Update Review** on the version page), and it becomes "Waiting for Review". The build
   stays the same. *On 2 October 2026, a day after replying to the 2.4.5(i) location question, the version was still
   Rejected with no answer from Apple: the reply alone had not put it back in the queue. Do steps 3 and 4 the same day as
   the reply.*

## Each release

1. Release the download as usual (`releasing.md`). Every release raises the build number, which the App Store requires.
2. From the same tagged commit, run `scripts/appstore.sh`. It stops with a pointer to this page if anything from the setup
   is missing, and refuses to package a build that still has the update check or a sandbox exception.
3. `open -a Transporter build/appstore/Nightwatch-<version>.pkg`, then **Deliver** (step 7).
4. In App Store Connect, create the new version and paste **What's New in This Version** (required for every update) from
   `scripts/release-notes.sh --appstore <version>`. It prints the release-history row as plain bullets without the release
   name, fails over Apple's 4,000 characters, and warns about download-only wording (GitHub, the DMG, the update check)
   to edit out first. Attach the build.
5. Paste **App Review Information › Notes** from *Notes for App Review* above, so every entitlement in the build is
   listed with where to see it. *The first update after 1.0.0 (1.2.0, if 1.0.0 is approved before the next release) adds two the reviewer has not seen:
   iCloud key-value storage (settings sync) and user-selected file access (Horizon › Measure from a photo).* Check the
   table against `codesign -d --entitlements - --xml` on `build/appstore`'s app, then go through *Before pressing Submit*.
6. **Save**, **Add for Review** and **Submit** (step 12), and confirm the status reads Waiting for Review. Review usually
   takes a day or two.

## Checking the review status

App Store Connect emails when a status changes, but not while a version sits Rejected or Ready for Review waiting on us:
1.0.0 lost a day that way (1–2 October 2026). `swift scripts/review-status.swift` asks the App Store Connect API for each
version's state, says it in plain words and exits 1 when something is waiting on us (Rejected, Ready for Review,
Pending Developer Release and the like), 0 when the next move is Apple's. Run it after replying to App Review, and
whenever a review has gone quiet.

One-off setup: a Team API key named "Nightwatch review status" with the **Sales and Reports** role only (read-only for
apps; roles add together, so add no other), made in Users and Access › Integrations › App Store Connect API. Its parts go
in the login keychain, from Terminal (`$USER` is typed as it is):

```
security add-generic-password -a "$USER" -s nightwatch-asc-key-id -U -w KEY_ID
security add-generic-password -a "$USER" -s nightwatch-asc-issuer-id -U -w ISSUER_ID
security add-generic-password -a "$USER" -s nightwatch-asc-key -U -w "$(base64 -i ~/Downloads/AuthKey_KEY_ID.p8)"
```

Then delete the downloaded `.p8`. That role cannot list review submissions (403), so the script reads version states
only, which show both states that went unnoticed. If the key is lost or leaked, revoke it on the same page and make
another.

## Listing text

Nothing here names Terry Pratchett, Discworld or the City Watch (rule 5.2.1). The description gives no web address: GitHub also offers the app as a download, which rule 2.3.10 (no alternative app marketplaces in metadata) could be read against, so the repository is reached through the Support URL instead. Telescope makers are described, not named,
in the name, subtitle and keywords.

- **Subtitle** (30 characters at most): Know when the sky is clear
- **Category:** Weather (secondary: Utilities)
- **Price:** Free
- **Age rating:** answer "None" throughout (4+)
- **Privacy policy URL:** https://github.com/rsutcliffe/nightwatch/blob/main/PRIVACY.md
- **Support URL:** https://github.com/rsutcliffe/nightwatch/discussions
- **Marketing URL:** https://delphi-dolphin.com/nightwatch
- **Copyright:** the year and the name, `2026 Richard Sutcliffe` (Apple adds the ©)
- **Keywords** (100 characters at most):
  `astronomy,astrophotography,telescope,stars,forecast,seeing,dark sky,aurora,moon,nebula,menu bar`

**Promotional text:**

> A quiet menu-bar app that tells you when tonight will be clear enough for a long imaging session, and what to point at.

**Description:**

> Nightwatch sits in your menu bar and watches the weather for you. When tonight looks clear for long enough, it sends a
> heads-up before sunset, then a nudge just before the clear spell begins. If the forecast turns, it tells you.
>
> Open it to see a sky score, the clear window, cloud by hour, darkness, the Moon, seeing, wind, dew risk and
> transparency, and the best targets for your telescope's field of view tonight.
>
> • Two forecasts compared: Apple Weather, with Open-Meteo as a second opinion, and 7Timer for seeing
> • Targets chosen for your field of view, with presets for popular smart telescopes and cameras
> • "How to shoot this" on every target: filter, exposure and frames for your telescope
> • Tonight's plan: your favourites in the order of their best time
> • Darker skies nearby, scored for tonight against home
> • Aurora alerts for your site, wherever you observe from
> • Tonight's events: the Moon passing in front of a star, comets and the space station
> • Spotlight and Shortcuts actions, so a shortcut can act on tonight's sky
> • A Text size setting, and small, medium and large desktop widgets
>
> No accounts, no advertising and no tracking. Nightwatch is open source.

**For the next submission** (owner, 8 October 2026: say more about the horizon; neither line is in the 1.6.4 listing).
Add after "Targets chosen for your field of view":

> • Your own horizon: mark the houses, trees or hills that block your sky, or measure them from a phone photo, and
>   Nightwatch only suggests what clears them

And, once the build has the rain line (#180), after "Two forecasts compared":

> • A warning when rain is forecast after the clear window, for a telescope left running outside

One screenshot of the horizon dial would back the first line: `docs/images/screenshot-horizon.png` is the README's.

## App privacy answers

Apple counts data as collected when it leaves the Mac and is kept longer than it takes to answer the request.
Nightwatch itself keeps nothing, but the forecast services receive coordinates, so declare them:

- **Data types:** Location › **Precise Location**. Open-Meteo receives the site to four decimal places, so it is precise
  by Apple's definition (three or more).
- **Purpose:** App Functionality only.
- **Linked to the user:** No.
- **Used for tracking:** No.

Nothing else is collected.

## Notes for App Review

Both 1.0.0 rejections asked for information, not fixes, and each answer cost days back in the queue. So the Notes answer
the questions before they are asked: what the app is for, how to set it up, the outside services, and **every
entitlement with the steps that show it in use**. App Review asks about any entitlement it cannot see working (guideline
2.4.5(i): on 1 October 2026 it asked about location, because the reviewer had not pressed "Use this Mac's location").

*On 7 October 2026 build 24 was rejected a third time, under 5.1.1(ii): "The app requests access to location data but did
not prompt users with a macOS permission request", with advice to include `NSLocationUsageDescription` and that
`NSLocationWhenInUseUsageDescription` "is only for iOS apps". The build had both keys. 1.6.1 dropped the iOS key, and the prompt
still appeared on macOS 27 from a clean copy of the app. But CoreLocation's header says `requestWhenInUseAuthorization`
(macOS 10.15 and later) "will do nothing" without `NSLocationWhenInUseUsageDescription`, and earlier macOS versions could
not be tested, so 1.6.2 carries both keys again with one specific sentence, and says why in the Notes. The likelier
reason the reviewer saw no prompt: macOS asks once per app and nothing resets it (`tccutil` has no Location service), so
a review Mac that answered in an earlier round never asks again. From 1.6.2 location is asked only from a button (the
welcome's, or "This Mac's location" in Settings), never at launch. Build 24 also had no Quit control and no way to open About, where the privacy link is (5.1.1(i)
asks for that link "within the app in an easily accessible manner"), so the store version moved to the current code
instead of patching 1.0.0. Attach a recording that shows the prompt appearing.*

*On 8 October 2026 the fourth submission went in: 1.6.4 (build 48), tested through TestFlight first, as 1.6.3 (build 47)
was. The version page was saved as 1.6.4 with build 48, the description below, these Notes with a recording of the
location prompt appearing, and five new screenshots. The reply in App Review's message thread carried four attachments
(two recordings and two stills). Then **Update Review** on the version page and **Resubmit to App Review**: the status
read "Waiting for Review" at about 15:19 BST.*

Paste this into App Review Information › **Notes** (plain ASCII: arrows and "›" did not survive the paste). Update it
whenever an entitlement or a setup step changes. The field takes 4,000 characters; this text is 3,952, as saved for the
1.6.4 resubmission on 13 October 2026, so any addition means cutting something.

```
Nightwatch is a menu-bar app for amateur astronomers: it forecasts whether tonight will be clear enough to observe or
photograph the sky, and suggests targets. No account or login. It has no Dock icon: click its
icon in the menu bar. To quit, click the power button at the top of the popover (Command-Q).

Setup: on first launch the Welcome window asks two questions. In step 2 "Where do you observe from?" click
"Use this Mac's location". macOS then asks "Nightwatch would like to use your current location": choose Allow.
(Or click "Add a site..." and search for a town: the app works the same without location.) Click "Start watching".
The menu-bar popover then shows tonight's forecast. macOS asks to allow notifications as the Welcome window closes.

Location is requested only when a button is pressed: the Welcome button above, or Settings > Where you observe >
"This Mac's location". Nothing asks at launch. If no prompt appears, Location Services is off on that Mac (the app
says so), or that Mac has already answered: macOS asks once per app. The attachments show the prompt.

Info.plist has NSLocationUsageDescription and also NSLocationWhenInUseUsageDescription (same sentence): CoreLocation's
header says requestWhenInUseAuthorization does nothing without it.

Alerts are local notifications: a heads-up an hour before sunset on a night that passes the go rule, and a nudge
just before the clear spell (the attached screenshot shows them).

Privacy policy: in the Welcome window (step 2) and at the foot of Settings.

Outside services (read only): Apple WeatherKit, Open-Meteo and 7Timer (forecasts; sent the site's coordinates),
Apple Maps (place search, sent what is typed; maps and place names, sent coordinates), AuroraWatch UK and the NOAA
Space Weather Prediction Center (aurora), CDS hips2fits (sky-survey images), NASA SVS (Moon image), Minor Planet
Center and CelesTrak (comets, space station). Nothing identifies the user.

Apple Weather attribution (5.2.5): wherever the app shows a forecast from Apple Weather it shows the Apple Weather
mark, which is itself the link to Apple's legal source page: popover footer (review-1.6.4-location.mp4 at 0:09, and the
stills sent in the reply), foot of the Targets sidebar, desktop widget, Siri and Spotlight cards. If Apple Weather does not
answer, the forecast comes from Open-Meteo, which the footer names; the mark is then absent because no Apple data is shown.

Also in the app: Spotlight and Shortcuts actions (Sky Score, Best Targets Tonight, Events Tonight, Clear Window
Tonight, Refresh Forecast, Show Target, Turn On or Off Clear-Sky Notifications) that read the forecast the app
already holds; on macOS 27, Siri can search Nightwatch's targets. "Add to Calendar" on an event page writes a calendar
file and needs no calendar access. "Start at login" (Settings > App) is off until the user turns it on.

Entitlements and where to see each one:
- App Sandbox: Mac App Store requirement.
- Location (personal-information.location): the two buttons above; used for the forecast, sunset, darkness and horizon
  for that place.
- Outgoing network connections (network.client): the services above.
- WeatherKit: the forecast in the popover and Targets window, with the Apple Weather mark (see above).
- iCloud key-value storage (ubiquity-kvstore-identifier): Settings > App, "Settings sync through iCloud to your other
  Macs"; signed out it reads "Not signed in to iCloud: settings stay on this Mac." Only the user's own settings sync, in
  their own iCloud account; nothing goes to the developer. Syncing needs a second Mac, so a reviewer can see only the caption.
- App Groups: forecast shared with the desktop widget (Edit Widgets > Nightwatch).
- User-selected files, read only: add a site (Settings > Where you observe > Add a site...), click Horizon..., then
  "Measure from a photo...": opens a photo the user chooses, reads its direction, lens and tilt, and does not keep it.
```

The table behind it, for checking against the build (`codesign -d --entitlements - --xml` on the store app):

| Entitlement | Used for | Where a reviewer sees it |
|---|---|---|
| `com.apple.security.app-sandbox` | Mac App Store requirement | — |
| `com.apple.security.personal-information.location` | One location fix (`LocationProvider`) | Welcome step 2; Settings › Where you observe |
| `com.apple.security.network.client` | Forecasts, images, data feeds, Apple Maps | Everything the popover and Targets show |
| `com.apple.developer.weatherkit` | Apple Weather forecast | Popover, Apple Weather mark |
| `com.apple.developer.ubiquity-kvstore-identifier` | Settings sync (#49) | Settings › App caption |
| `com.apple.security.application-groups` | Forecast shared with the widget (app and widget) | Desktop widget |
| `com.apple.security.files.user-selected.read-only` | Opening a photo to measure a site's horizon | Settings › Where you observe › Horizon… › Measure from a photo… |

Deliberately **not** in the store build (`scripts/appstore.sh` strips them and fails if they return): the temporary
sandbox exceptions, which exist only to import 0.6 settings that an App Store user never had, so a reviewer could never
see them used. The download keeps them.

User-selected file access was **not** stripped from 1.0.0, whatever this page said before: the submitted package
(`build/appstore/Nightwatch-1.0.0.pkg`, build 24) carries `com.apple.security.files.user-selected.read-only`, checked on
2 October 2026 with `pkgutil --expand-full` and `codesign -d --entitlements`. In 1.0.0 it serves only the Welcome
window's "Import settings..." step, which appears only when 0.6 settings are found, so a reviewer cannot see it; the 1.0.0
Notes say so. From 1.1 it also has a visible use (Measure from a photo). Check the real package, never this page.

### Before pressing Submit

- The Notes above are current, and list every entitlement the build carries.
- A short screen recording (launch, Welcome with "Use this Mac's location", popover, Targets, Settings, widget)
  is in App Review Information › **Attachment**, not only in a reply. It must also show the Apple Weather mark in
  the popover footer, the Targets sidebar and the widget, and the legal page opening from the mark (5.2.5), the iCloud
  caption in Settings › App, Siri or Shortcuts answering, and Measure from a photo. The 1.6.4 submission carried two
  whole-desktop recordings: `review-1.6.4-location.mp4` (3 minutes, in the Notes attachment, read in App Store
  Connect on 13 October 2026) and `review-1.6.4-widget-shortcut.mp4` (90 seconds, in the reply thread). Between them
  they show the popover, Targets, Settings, the widget and Shortcuts, so the Apple Weather mark is on screen, but only
  a few pixels tall and never pointed at, and the legal page is never opened. The store screenshots also show the
  mark, and the app already carried it everywhere Apple lists. Apple's 13 October message is a request to confirm
  ("appears to support WeatherKit but we need to confirm"), so why the reviewer did not see the mark is not known;
  one possibility is that Apple Weather did not answer on their Mac. Add close-up clips of each thing a reviewer must
  see, in one walkthrough covering every entitlement, kept for every later submission.
- After **Submit** (or **Resubmit to App Review**), the status reads **Waiting for Review**. "Ready for Review"
  means not submitted.

### Guideline pre-flight (13 October 2026)

Written after the fourth rejection (1.6.4, guideline 5.2.5, Apple Weather attribution), against the live App Review
Guidelines text and what App Store Connect holds for 1.6.4. Rule of the audit: for each guideline a reviewer could use
to ask "where do I see this?", the answer is in the Notes AND on the recording. Re-run it before each submission.

| Guideline | A reviewer could ask | Evidence today | Status |
|---|---|---|---|
| 2.1 completeness | How do I use it? Any login? Is every feature reachable? | No sign-in (box unticked in App Store Connect); Notes give setup and every entitlement; contact details filled in | OK: two recordings (3 min and 90 s) cover the main flow. **Gap:** nothing points at the small things (the Apple Weather mark, the iCloud caption), so add close-ups to one walkthrough |
| 2.3.3, 2.3.10 metadata | Do screenshots show the app in use? Any other platform or marketplace named? | Screenshots of the running app; description has no web address and the download is not mentioned | OK |
| 2.3.6 age rating | Honest answers? | None throughout, 4+ | OK |
| 2.4.5(i) sandbox | Entitlements justified? | Seven listed with where each is seen; the temporary exceptions are stripped by `scripts/appstore.sh` | OK, once the recording shows each one |
| 2.4.5(iii) no login launch without consent | Does it start by itself? | "Start at login" is off until switched on; no Dock icon; Quit in the popover | OK |
| 2.4.5(vii) updates only through the store | Does it update itself? | The update check is gated by `Distribution.checksForUpdates`, off in the store build | OK |
| 2.5.11 Shortcuts and Siri | Do the actions fit the app? | Seven actions, all about the forecast and targets; phrases name Nightwatch first | OK; show one on the recording |
| 2.5.16 widgets | Related to the app? | Widget shows tonight's sky score | OK; show it on the recording |
| 4.2 minimum functionality | Is it more than a web page? | Native forecast, planner, charts, widget, Shortcuts | OK |
| 5.1.1(i) privacy policy | Link in metadata and in the app? | App Store Connect holds `PRIVACY.md` on GitHub; in the app at Welcome step 2 and the foot of Settings | OK. `PRIVACY.md` also changes in PR 182, so that PR waits until 1.6.4 is approved |
| 5.1.1(ii), (iv) consent | Does it ask before location? Does it work without? | Asked only from a button; "Add a site..." works without it; the 1.6.4 recording shows the prompt | OK |
| 5.1.2 data sharing, privacy labels | Where do coordinates go? Do the labels match? | Coordinates go to Apple WeatherKit, Open-Meteo and 7Timer; label says Precise Location, not linked to you, app functionality | OK |
| 5.1.5 location | Is it needed? | Forecast, sunset, darkness and horizon for where you are | OK |
| 5.2.1 trademarks | Third-party names? | No Discworld or Pratchett names in the listing; telescope makers are described, not named | OK |
| 5.2.2 third-party services | Permission for the data? | Open-Meteo (CC BY 4.0), 7Timer, NOAA, AuroraWatch UK, CDS and DSS (non-profit use), NASA SVS, Minor Planet Center, CelesTrak; credited in About and `NOTICE` | OK **while the app stays free with no ads**, which several terms require |
| **5.2.5 Apple products** | **Does it show the Apple Weather mark and legal link?** | Mark and link in the popover footer, Targets sidebar, widget and Siri cards (code); the recordings show it only in passing, a few pixels tall | **Rejected 13 October** (a request to confirm). Reply with a close-up recording, add the Notes paragraph above |
| Export compliance | Encryption? | `ITSAppUsesNonExemptEncryption` is false | OK |
| Privacy manifest | Required-reason APIs declared? | `PrivacyInfo.xcprivacy` is in the app | OK |

## Screenshots

Mac screenshots are 16:10: 1280 × 800, 1440 × 900, 2560 × 1600 or 2880 × 1800 pixels, one to ten of them, PNG or JPEG
with no transparency. Use 2880 × 1800, and take them at a public dark-sky site as for the README (the 1.0 set used the North York Moors),
never at home.
