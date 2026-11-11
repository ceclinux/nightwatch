# Nightwatch for iPhone and iPad: product requirements

*Status, 26 October 2026: built and under test, not yet submitted. This document began as the plan for version 1 and has been brought up to date; the original smaller scope is recorded under "Not in version 1" as it was decided then, and what shipped instead is listed in "What the app does now".*

The app is the iPhone and iPad version of the one "Nightwatch: Clear Sky Alerts" App Store record (universal purchase, record 6816390602), in this repository under `Phone/`.

## One line

A free iPhone and iPad companion to the Nightwatch Mac app: it tells you, in five seconds, whether tonight is worth setting
up the telescope, and speaks up on your phone when it is.

## Why

The go or no-go decision is acted on outdoors, with a phone, but Nightwatch speaks only on the Mac, and Mac notifications
do not reach an iPhone (issue #58 in the Mac repository).

## Who

Owners of smart telescopes and cameras who observe from a garden, a balcony or a dark site. In the field they usually have
a cellular iPad, or an iPhone with data tethered to it, so a connection is likely but not guaranteed.

## Product principles

- **A five-second answer.** The verdict first, the reasons under it, specialist terms kept and explained.
- **Honest.** "No clear window tonight" is a good answer. A forecast that is old says how old.
- **The Mac's words and design.** Same verdict wording, sky-score bezel, clear-sky bars, dark palette. One source of truth for
  the sky maths: SkyCore, from the Mac repository.
- **Connected first, offline as the fallback.** Refresh when opened if the forecast is over 30 minutes old. Frugal with data:
  optional downloads wait for a cheap connection (not cellular, not Personal Hotspot, not Low Data Mode).
- **No glare.** A red night mode that keeps dark adaptation. The Apple Weather mark is never recoloured.
- **Free, no account, no paywall, no tracking.** The data terms require it to stay non-commercial.

## Version 1: the smallest closed loop

Open the app, see tonight's answer for your saved site, optionally change site, and be alerted by notification. Nothing a
person can get lost in.

1. First run, at most three screens: what it does; where you observe from (sites arrive from the Mac through iCloud, else
   "Use this iPhone's location" or add a site by name); notifications, asked for after the verdict is shown.
2. Tonight: score bezel, headline, clear window, clear-sky bars, six tiles (Dark, Moon, Seeing, Wind, Dew risk or Frost
   likely, Transparency), the best three targets, the source footer with Apple Weather's mark and legal link.
3. Sites and a small Settings: alerts on or off, quiet hours, red night mode, the go rule read-only from the Mac.
4. Alerts: heads-up an hour before sunset, nudge before the window, cancel notice. Local notifications queued from the
   latest forecast by SkyCore's alert engine, rebuilt at every refresh. Background refresh is best-effort; nothing is queued
   from a forecast more than six hours old at the moment it would fire.

## What the app does now

Beyond the closed loop above, the app has Tonight, Plan (tonight and tomorrow night, with favourites), Targets (by type, with target pages and "how to shoot
this"), the week ahead, dark sites with small maps, events (meteor showers, space station passes, eclipses and occultations), horizon editing, a red night
mode, small, medium and large widgets, a Lock Screen card for the clear window, Siri, Spotlight and Shortcuts, aurora alerts, and settings sync with the
Mac through iCloud. It is free, with no account and no tracking, as decided.

## Not in version 1, on purpose (the original decision, since superseded)

Targets list and detail, Tonight's plan, the week ahead, favourites, dark sites, events, horizon editing, Siri and Shortcuts, widgets, Apple Watch. All but
Apple Watch (decided: no) were built after this was written, once the Mac's 1.7.0 shipped.

## Decisions made

One repository (the phone app lives under `Phone/` here, since PR 208) and one App Store record with the Mac app; SkyCore is shared, not copied; iOS 17 and
later; the Mac's bundle IDs (`io.github.rsutcliffe.nightwatch` and `.widget`), version 1.0.0; no community features and no user-research gate; submit
after the search case Apple opened on the Mac record is settled.

## Open, to settle before release

The search case (Apple case 103007210525); screenshots recaptured on a moonless night (6 to 12 November 2026) and a widgets image from a real Home
Screen; Apple's attribution wording for the mark in red mode; the background-refresh cadence in practice. The privacy text is in the Mac repository's
`PRIVACY.md`, with the phone's section held in a draft PR until submission.
