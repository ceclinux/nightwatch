# Nightwatch privacy policy

*Last updated 29 September 2026 (iCloud settings sync). Applies to Nightwatch 0.7.0 and later, from GitHub, delphi-dolphin.com or the Mac App Store.*

Nightwatch is a free, open-source Mac app by Richard Sutcliffe. It has no accounts, no analytics, no advertising and no
tracking. The developer collects no data about you: nothing is sent to the developer, and there is no Nightwatch server.

## What stays on your Mac

- **Your settings:** your saved sites, telescope, alert choices and so on. If you are signed in to iCloud, they are also
  kept in your iCloud account so your other Macs share them (Apple's iCloud key-value storage, under
  [Apple's privacy policy](https://www.apple.com/legal/privacy/)); Nightwatch's developer cannot see them.
- **Your location**, if you let Nightwatch use it. It is used to work out sunset, darkness and what is visible from where
  you are.
- **Caches:** forecasts, tonight's plan, sky-survey images and the place names of computed dark spots, plus a record of which alerts tonight has already sent, so
  none is sent twice.

It is kept in Nightwatch's own folders on your Mac:

- `~/Library/Containers/io.github.rsutcliffe.nightwatch` (settings, caches and alert records);
- `~/Library/Containers/io.github.rsutcliffe.nightwatch.widget` and the shared
  `~/Library/Group Containers/…io.github.rsutcliffe.nightwatch` (the desktop widget's copy of tonight, including your
  site's name);
- if you used version 0.6 or earlier, its old folders `~/Library/Application Support/Nightwatch` and
  `~/Library/Caches/Nightwatch`, which 0.7.0 copies from and leaves untouched.

Delete the app and those folders, and it is gone.

## What is sent over the internet, and to whom

To fetch forecasts, Nightwatch sends **the coordinates of the place being forecast** (your location or a saved site, and
nearby dark-sky sites if that feature is on). They go to:

- **Apple Weather (WeatherKit)**, on builds signed for it. macOS makes these requests on Nightwatch's behalf and
  identifies the app to Apple, as it does for every app using Apple Weather. See
  [Apple's privacy policy](https://www.apple.com/legal/privacy/).
- **[Open-Meteo](https://open-meteo.com/en/terms)**, for cloud cover and a second opinion. No name, account or device
  identifier goes with the coordinates.
- **[7Timer!](https://www.7timer.info)**, for seeing and transparency. The same applies.
- **Apple Maps**, for the name of the nearest town or village to each computed dark spot, if that feature is on. Each
  spot is looked up once and the answer kept; a lookup that fails is tried again an hour later. macOS makes these
  requests on Nightwatch's behalf, as it does for Apple Weather. See [Apple's privacy policy](https://www.apple.com/legal/privacy/).

Other requests carry nothing about you or your location:

- **[AuroraWatch UK](https://aurorawatch.lancs.ac.uk)**, for the aurora status, if aurora alerts are on.
- **The Minor Planet Center and CelesTrak**, for comet and ISS data.
- **CDS (Strasbourg)**, for sky-survey images. It receives the sky position of the target being shown, not yours.
- **NASA's Scientific Visualization Studio**, for the Moon image. It receives the date and hour, nothing about you.
- **GitHub**, once a day, to check for a newer version. This is in the download from GitHub or delphi-dolphin.com
  only, and Settings › Updates turns it off. The Mac App Store version has no update check: the App Store updates it.

Nightwatch's own requests (all of the above except Apple Weather and Apple Maps) identify themselves as Nightwatch and its version, as
the services ask. These services receive your IP
address as part of any internet request, and their own privacy policies apply. Nightwatch shares nothing else with them
or with anyone.

## Permissions

- **Location** is asked for when you choose "Use this Mac's location", or at launch when your settings (including
  those copied from 0.6) observe from this Mac. You can refuse it and add a site by hand, or turn it off later in
  System Settings › Privacy & Security › Location Services.
- **Notifications** are used only for Nightwatch's own alerts.

## Children

Nightwatch collects no personal data from anyone, including children.

## Changes and contact

Changes to this policy are published here, in the app's public repository, with the date above. Questions:
[GitHub Discussions](https://github.com/rsutcliffe/nightwatch/discussions), or
[open an issue](https://github.com/rsutcliffe/nightwatch/issues).
