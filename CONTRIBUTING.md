# Contributing to Nightwatch

Thank you for wanting to help. Nightwatch has one narrow job: tell you when tonight is clear and what is worth pointing a telescope at. It stays useful by staying small, so most of contributing is agreeing what to change before any code is written.

## Open an issue first

Please open an issue before you start a pull request, and say what you would like to change and why. It takes a few minutes and saves you building something that does not fit. A pull request that arrives without an issue may be closed with a pointer back here; that is no comment on the work.

Bug reports are always welcome. Say which version you have (Settings › About Nightwatch), what you did and what you saw.

## Changes that fit

- Bug fixes.
- Telescope presets. Copy an existing entry in `Sources/SkyCore/Resources/presets/telescopes.json`, fill in the field of view in degrees and the battery life in hours, and name where the figures came from in `source`. The maker's own page is best. A shooting tip in `Sources/SkyCore/ShootingTips.swift` is welcome and optional.
- Corrections to data, wording and documentation.

## Changes that do not fit

These have been considered and are not planned:

- Builds for Intel Macs. Nightwatch is for Apple silicon.
- Telescope control.
- A planetarium or augmented-reality view of the sky.
- Observing logs, accounts or anything social.
- A red night-vision mode.
- Alerts for anything but the night sky, such as golden hour and blue hour.

If your idea is on that list, you are welcome to fork. The licence is MIT, so you may build and share your own version.

## Pull requests

- One change in each pull request, as small as it can be.
- `scripts/test.sh` must pass. Add a test with a fix where one is possible.
- `scripts/build-app.sh --no-install` builds the app without installing it.
- Say what you tested and how, and what you could not test.
- Your first pull request's checks wait for approval before they run.
