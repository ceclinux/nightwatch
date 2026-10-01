# Releasing Nightwatch on the Mac App Store

The App Store version, **"Nightwatch: Clear Sky Alerts"**, is built from the same code as the download. The only
difference is that it has no update check, because the App Store updates it (rule 2.4.5(vii)). That switch is the one
`#if APPSTORE` in `Sources/Nightwatch/Distribution.swift`, and a test keeps it the only one. CI builds both on every pull
request.

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
   stays the same.

## Each release

1. Release the download as usual (`releasing.md`). Every release raises the build number, which the App Store requires.
2. From the same tagged commit, run `scripts/appstore.sh`. It stops with a pointer to this page if anything from the setup
   is missing, and refuses to package a build that still has the update check, a sandbox exception or user-selected file access.
3. `open -a Transporter build/appstore/Nightwatch-<version>.pkg`, then **Deliver** (step 7).
4. In App Store Connect, create the new version and paste **What's New in This Version** (required for every update) from
   `scripts/release-notes.sh --appstore <version>`. It prints the release-history row as plain bullets without the release
   name, fails over Apple's 4,000 characters, and warns about download-only wording (GitHub, the DMG, the update check)
   to edit out first. Attach the build, then **Save**, **Add for Review** and **Submit** (step 12). Review usually takes a
   day or two.

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
> • Darker skies nearby, scored for tonight against home
> • Aurora alerts from AuroraWatch UK
> • Small, medium and large desktop widgets
>
> Free, with no accounts, no advertising and no tracking. Nightwatch is open source.

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

Paste this into App Review Information › **Notes** (plain ASCII: arrows and "›" did not survive the paste). Update it
whenever an entitlement or a setup step changes.

```
Nightwatch is a menu-bar app for amateur astronomers: it forecasts whether tonight will be clear enough to observe or
photograph the sky, and suggests what to point a telescope at. No account or login.

Setup: on first launch the Welcome window asks two questions. In step 2 "Where do you observe from?" choose
"Use this Mac's location" and Allow (or "Add a site..." and search for a town). The menu-bar popover then shows
tonight's forecast. Alerts fire only on nights that pass the go rule; to see one sooner, lower
Settings > Go rule > "Clear for at least" to 1 h on a partly clear night.

Outside services (read only, no user data except the site's coordinates for forecasts): Apple WeatherKit,
Open-Meteo and 7Timer (forecasts), AuroraWatch UK (aurora status), CDS hips2fits (sky-survey images), NASA SVS
(Moon image), Minor Planet Center and CelesTrak (comets, space station), Apple Maps (place search and maps).

Entitlements and where to see each one:
- App Sandbox: required for the Mac App Store.
- Location (personal-information.location): Welcome step 2 "Use this Mac's location"; Settings > Where you observe >
  "This Mac's location"; Settings > Where you observe > Add a site... > "Use this Mac's location". One fix at
  kilometre accuracy, used to work out sunset, darkness and what is visible.
- Outgoing network connections (network.client): the forecasts, images and data above.
- WeatherKit: the forecast in the popover; the Apple Weather mark under it links to the legal attribution.
- iCloud key-value storage (ubiquity-kvstore-identifier): Settings > App, "Settings sync through iCloud to your
  other Macs". Change a setting on one Mac and it appears on another signed in to the same Apple Account.
- App Groups: the app shares tonight's forecast with its desktop widget. Add the Nightwatch widget from the desktop's
  Edit Widgets; it shows the same sky score as the popover.
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

Deliberately **not** in the store build (`scripts/appstore.sh` strips them and fails if they return): the temporary
sandbox exceptions and `com.apple.security.files.user-selected.read-only`. Both exist only to import 0.6 settings,
which an App Store user never had, so a reviewer could never see them used. The download keeps them.

### Before pressing Submit

- The Notes above are current, and list every entitlement the build carries.
- A short screen recording (launch, Welcome with "Use this Mac's location", popover, Targets, Settings, widget)
  is in App Review Information › **Attachment**, not only in a reply.
- After **Submit** (or **Resubmit to App Review**), the status reads **Waiting for Review**. "Ready for Review"
  means not submitted.

## Screenshots

Mac screenshots are 16:10: 1280 × 800, 1440 × 900, 2560 × 1600 or 2880 × 1800 pixels, one to ten of them, PNG or JPEG
with no transparency. Use 2880 × 1800, and take them at a public dark-sky site as for the README (the 1.0 set used the North York Moors),
never at home.
