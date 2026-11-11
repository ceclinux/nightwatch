# Nightwatch privacy policy

*Last updated 26 October 2026 (the iPhone and iPad app added). Applies to Nightwatch for Mac 0.7.0 and later, from GitHub, delphi-dolphin.com or the Mac App Store, and to Nightwatch for iPhone and iPad 1.0.0 and later, from the App Store.*

Nightwatch is a free, open-source app for Mac, iPhone and iPad by Richard Sutcliffe. It has no accounts, no analytics, no advertising and no
tracking. The developer collects no data about you: nothing is sent to the developer, and there is no Nightwatch server.

## What stays on your Mac

- **Your settings:** your saved sites, telescope, alert choices and so on. If you are signed in to iCloud, they are also
  kept in your iCloud account so your other Macs share them (Apple's iCloud key-value storage, under
  [Apple's privacy policy](https://www.apple.com/legal/privacy/)); Nightwatch's developer cannot see them.
- **Your location**, if you let Nightwatch use it. It is used to get the weather forecast for where you are, and to work
  out sunset, darkness and what is above your horizon. Nightwatch keeps it on this Mac; only its coordinates go to the
  forecast services listed below, with nothing that says whose they are.
- **Spotlight:** tonight's summary and tonight's targets are added to this Mac's own Spotlight index, so Spotlight and
  Siri can find them. They are replaced at every refresh.
- **Shortcuts:** Nightwatch's actions hand tonight's answer (the sky score, targets, events, or whether there is a clear
  window) to the Shortcuts app on this Mac. What a shortcut of yours then does with it is up to that shortcut.
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
- **[Open-Meteo](https://open-meteo.com/en/terms)**, for cloud cover and a second opinion; its air-quality service, for
  how much smoke, dust or haze is in the air at each place forecast; and once for each saved site
  (and again if it moves) the ground's height at points up to 20 km around it, for the hills on its horizon. No name,
  account or device identifier goes with the coordinates.
- **[7Timer!](https://www.7timer.info)**, for seeing and transparency. The same applies.
- **[MET Norway](https://api.met.no)**, for cloud cover, only when Apple Weather and Open-Meteo cannot be read. The same applies.
- **Apple Maps**, to find a dark car park near each computed dark spot and the name of its town or village, and a small
  map of each dark site on its card, if that feature is on; Open in Maps hands the site's position to the Maps app. In
  Add a site, the place name you type is sent to Apple Maps to suggest places, and the one you choose is drawn on a small
  map; your own location is not sent. Each
  spot is looked up once and the answer kept; a lookup that fails is tried again an hour later. macOS makes these
  requests on Nightwatch's behalf, as it does for Apple Weather. See [Apple's privacy policy](https://www.apple.com/legal/privacy/).

Other requests carry nothing about you or your location:

- **[AuroraWatch UK](https://aurorawatch.lancs.ac.uk)**, for the aurora status at sites in the UK and Ireland, if aurora alerts are on.
- **[NOAA's Space Weather Prediction Center](https://www.spaceweather.gov/products/aurora-30-minute-forecast)**, for the aurora forecast everywhere else, if aurora alerts are on. Nightwatch downloads the forecast for the whole world and reads your site's point on this Mac, so your location is not sent.
- **The Minor Planet Center and CelesTrak**, for comet and ISS data.
- **CDS (Strasbourg)**, for sky-survey images. It receives the sky position of a target being shown, and of tonight's suggested targets and those in your plan so their pictures are ready, not yours.
- **NASA's Scientific Visualization Studio**, for the Moon image. It receives the date and hour, nothing about you.
- **GitHub**, once a day, to check for a newer version. This is in the download from GitHub or delphi-dolphin.com
  only, and Settings › Updates turns it off. The Mac App Store version has no update check: the App Store updates it.

**Measure from a photo** (Settings › Where you observe › Horizon…) reads a photo you choose, on this Mac only: which way it
faced, its lens, the phone's tilt and where it was taken. Nothing from it is sent anywhere, and the photo is not copied or
kept. Only the heights you use are saved, and the photo's position only if you press Move to put the site there.

Nightwatch's own requests (all of the above except Apple Weather and Apple Maps) identify themselves as Nightwatch and its version, as
the services ask. These services receive your IP
address as part of any internet request, and their own privacy policies apply. Nightwatch shares nothing else with them
or with anyone. None of them receives your name, an account or any identifier from Nightwatch, so none holds anything
from Nightwatch that says who you are.

## Permissions

- **Location** is asked for only when you press a button for it: "Use this Mac's location" in the welcome, or
  "This Mac's location" in Settings › Where you observe. Nightwatch never brings up the request by itself. The request
  says what the location is for. You can refuse it and add a site by typing a place name, and Nightwatch works the
  same; or turn it off later in System Settings › Privacy & Security › Location Services.
- **Notifications** are asked for as the welcome closes, after it has said what they are for.
  They are used only for Nightwatch's own alerts.

## Keeping, deleting and changing your mind

- The developer holds no data about you, so there is nothing for the developer to keep, hand over or delete.
- What Nightwatch keeps is on your Mac, and your settings are also in your own iCloud account when this Mac is signed in
  to iCloud. Settings › App › Reset config clears your settings, on all your Macs when they sync. Deleting the app and
  the folders listed above removes the rest.
- To stop Nightwatch using your location, turn it off in System Settings › Privacy & Security › Location Services, and
  choose a saved site in Settings › Where you observe. To stop alerts, turn them off in Settings or in System Settings ›
  Notifications.
- The services listed above receive coordinates and your IP address when Nightwatch asks them for data. How long they
  keep their own logs is set by their policies, linked above; Nightwatch sends them no name, account or identifier to
  tie a request to you.

## Nightwatch for iPhone and iPad

Everything above about forecasts, services, permissions and children applies to the iPhone and iPad app too, with "Mac" read as "iPhone or iPad".
These parts differ.

**What stays on your iPhone or iPad**

- **Your settings:** your saved sites, alert choices and quiet hours. If you are signed in to iCloud they are also kept in your iCloud account,
  so your Mac, iPhone and iPad share them (Apple's iCloud key-value storage, under [Apple's privacy policy](https://www.apple.com/legal/privacy/));
  the developer cannot see them. Red night mode and the Lock Screen card choice are kept on each device only.
- **Your location**, if you let Nightwatch use it. It is asked for only when you press "Use this device's location". It is used once, to make a
  saved site for where you are, and only the site's coordinates go to the forecast services above.
- **The last forecast, tonight's plan and a record of which alerts have been sent**, so the app works without a connection and sends no alert twice.
- **Spotlight and Shortcuts:** tonight's summary is added to this device's Spotlight index, and Nightwatch's actions hand tonight's answer to the
  Shortcuts app, as on the Mac. What a shortcut of yours then does with it is up to that shortcut.

**The widgets and the Lock Screen card.** The app hands the widgets tonight's answer through an App Group shared only with them on the same device
(the site's name and Apple Weather's mark are in it). The widgets fetch nothing. The Lock Screen card is a Live Activity the app starts and updates
on the device; no Nightwatch server and no push service is involved.

**Background refresh.** iOS decides when to let the app read a fresh forecast and re-queue its alerts; it makes the same requests as when the app is open.

**Measure from a photo** uses the system's photo picker, so Nightwatch does not ask for access to your photo library. The photo is read on the
device, not kept or sent; only the height you set is saved.

**Keeping, deleting and changing your mind.** The developer holds no data about you. Delete the app to remove what it keeps on the device.
Your settings stay in your iCloud account for your other devices; remove them with Reset in the Mac app, or in iPhone Settings › [your name] ›
iCloud › Manage Account Storage. To stop Nightwatch using your location or sending alerts, change it in iOS Settings › Nightwatch.

## Children

Nightwatch collects no personal data from anyone, including children.

## Changes and contact

Changes to this policy are published here, in the app's public repository, with the date above. Questions:
[GitHub Discussions](https://github.com/rsutcliffe/nightwatch/discussions), or
[open an issue](https://github.com/rsutcliffe/nightwatch/issues).
