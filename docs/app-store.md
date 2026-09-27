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

## Each release

1. Release the download as usual (`releasing.md`). Every release raises the build number, which the App Store requires.
2. From the same tagged commit, run `scripts/appstore.sh`. It stops with a pointer to this page if anything from the setup
   is missing, and refuses to package a build that still has the update check or a sandbox exception.
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

> Nightwatch needs a place to forecast for. On first launch, choose "Use this Mac's location" (and Allow) or "Add a
> site…". The popover then shows tonight's forecast. Alerts only fire on nights that meet the go rule, so the fastest
> check is the popover and Settings; notifications can be seen by lowering Settings › Go rule › Clear for at least to
> 1 h on a partly clear night. The app uses no login.

## Screenshots

Mac screenshots are 16:10: 1280 × 800, 1440 × 900, 2560 × 1600 or 2880 × 1800 pixels, one to ten of them, PNG or JPEG
with no transparency. Use 2880 × 1800, and take them at a public dark-sky site as for the README (the 1.0 set used the North York Moors),
never at home.
