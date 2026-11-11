# Featuring nomination: Nightwatch on iPhone and iPad (draft, 3 November 2026)

For the owner to enter in App Store Connect > the app > **Featuring > Nominations > + > Create Nomination**, then **Submit Nomination**. Nothing has
been entered or submitted. Procedure and Apple's rules: the app-store-optimiser skill's `references/featuring-nominations.md` (Apple's pages read 3 November 2026).
Apple says there is no checklist and a nomination is a request to be considered, not a booking. Editors look at the product page, accessibility,
the experience and ratings, so the page below is what they will see.

Roles that can submit: Account Holder, Admin, App Manager, Marketing. Lead time: Apple's developer page says two weeks minimum and up to three months;
the App Store Connect tip says three weeks. **Submit by 6 November for a date from 1 December.**

| Field | Entry |
|---|---|
| **Name** (internal) | Nightwatch on iPhone and iPad |
| **Type** (cannot be changed after submitting) | **App Enhancements** (new features and platforms for an existing app). *App Launch* is for a new app or pre-order, and the record has been live since 20 October, so it fits less well |
| **Description** | Nightwatch tells amateur astronomers whether tonight is worth setting up the telescope. It compares two forecasts, finds the clear window, and ranks targets for the user's own telescope field of view and their own horizon, with a heads-up before sunset and a warning if the forecast turns. This update brings it to iPhone and iPad: one free purchase now covers Mac, iPhone and iPad, with Home Screen widgets, a Lock Screen card when a clear window opens, a red night mode that keeps eyes dark-adapted, and a ready-made set of colour target pictures so the app keeps working when the sky survey's website cannot be reached. No accounts, no advertising and no tracking; the code is open source. |
| **Publication date or range** | 1 to 15 December 2026 (your device's time zone) |
| **Related apps** (up to 10; cannot be changed after submitting) | None. The account's other apps (the two children's games) are a different audience; listing them would not help this nomination |
| **Platforms** | iPhone, iPad, Mac |
| **Countries or regions / localizations** | All regions (the default); English (U.K.) |
| **In-App Event** | None yet. Attach the December "Moonless week" event once it is approved, as early as possible |
| **Supplemental materials** (up to 5 URLs) | 1. https://delphi-dolphin.com/nightwatch  2. https://github.com/rsutcliffe/nightwatch  3. https://github.com/rsutcliffe/nightwatch/blob/main/PRIVACY.md  (add a TestFlight public link only if you create one) |
| **Helpful details** | Red night mode for dark adaptation. Larger Text and Increase Contrast, Reduce Transparency and Reduce Motion are honoured on Mac and iPhone/iPad; VoiceOver labels on the controls; text colours checked at 4.5:1 or better. |

## What is true and where it is checked
- *Two forecasts compared, clear window, targets for the user's field of view and horizon, heads-up before sunset:* the live listing text and `docs/product-overview.md`.
- *One free purchase for Mac, iPhone and iPad; widgets; Lock Screen card; red night mode:* the live iOS 1.0 listing and `Phone/` (the Lock Screen card needs Live Activities switched on).
- *Ready-made colour pictures, with a greyscale fallback:* PR 239 and the prerelease `survey-set-1` (in review as Mac 1.7.2 and iPhone/iPad 1.0.1; **the sentence is only true once those are approved, so submit the nomination after approval, or say "is arriving"**).
- *No accounts, no advertising, no tracking; open source:* `PRIVACY.md` and `LICENSE` (MIT); `check_claims.py` passed these on 3 November.
- *Accessibility:* `docs/uat.md` items 26, 60 to 63 and 91 pass (contrast script 4.5:1; Increase Contrast, Reduce Transparency, Reduce Motion, Larger Text; VoiceOver labels). Item 120 (Extra large text with Reduce Transparency and Increase Contrast) is marked "not yet seen", so the nomination does not claim it. The code counts: 21 and 34 accessibility labels on phone and Mac, Dynamic Type or the Text size setting on both. The Mac has a Text size setting, not Dynamic Type; the wording says "Larger Text", which macOS has.
- **No claim of any award or Apple recognition, and none to be added.**

## Before pressing Submit
1. The two reviews have passed, so the picture-set sentence is true.
2. The product page itself is the strongest asset: the first three screenshots should tell one story. Recapture them in the moonless week (6 to 12 November) and ship them with the next version; a nomination submitted after that is the better one. If you submit this week, the lead time still holds for 1 December.
3. Record the submitted date here and check back on it: ____ / ____
