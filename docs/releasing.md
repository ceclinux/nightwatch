# Releasing Nightwatch for download

A release is a disk image, `Nightwatch-<version>.dmg`, signed with a Developer ID certificate and notarised by Apple, so it
opens on anyone's Mac without a security warning. `scripts/release.sh` does the whole job; the one-off setup below comes
first. Nightwatch is not sandboxed, so it cannot go on the Mac App Store as it stands; this is the route for a download
from a website or a GitHub release.

## Automated ARM / Intel builds

The **Build macOS ARM / Intel** GitHub Actions workflow (`.github/workflows/build-intel.yml`) publishes a prerelease after
successful push builds on `main`, `intel-build`, `intel` or `chinese-translation`, and after a manual **Run workflow** build.
Every run builds Apple Silicon and Intel separately in a two-job matrix and checks each binary's architecture. Both builds
must succeed before a single release is published with both ZIPs. Pull requests targeting `main`, `intel-build` or `intel`
build and upload artifacts but never publish releases. Manual runs also build both architectures; no architecture selection
is needed.

Each run attempt gets a unique tag, `build-<run-id>-<attempt>`, pointing at the built commit. Both assets are required:

- `Nightwatch-macOS-AppleSilicon-arm64.zip` — Apple Silicon (M-series) Macs.
- `Nightwatch-macOS-Intel-x86_64.zip` — Intel Macs.

The release link also appears in the release job's summary. Rerunning a workflow creates a separate prerelease rather than
overwriting an earlier build. These prereleases do not replace the latest stable release.

Publishing uses the built-in `GITHUB_TOKEN` with `contents: write` only in the release job; no additional secret is needed.
Repository or organisation policies must allow that permission and creation of the `build-*` tags.
These apps are ad-hoc signed, **not notarised**, and omit the desktop widget and helper. macOS may block them on first
launch. For the signed and notarised DMG, use the local release process below.

## One-off setup (the account holder, about 15 minutes)

1. **Developer ID Application certificate.** In Xcode: Settings › Accounts › your team › Manage Certificates › + ›
   Developer ID Application. Or on the web: [Create Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
   Only the account holder can create one. It lands in your login keychain; keep a backup, since it signs every release.
2. **A Developer ID provisioning profile for the app.** At developer.apple.com › Certificates, Identifiers & Profiles ›
   Profiles › +, choose Developer ID, the App ID `io.github.rsutcliffe.nightwatch` (it already has WeatherKit), and the
   certificate from step 1. Download it, then copy it where Xcode keeps profiles, which is where the script looks
   (double-clicking installs it under System Settings › General › Device Management instead, which the script cannot read):

   ```bash
   P=~/Downloads/Nightwatch.provisionprofile; cp "$P" ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/"$(security cms -D -i "$P" | plutil -extract UUID raw -)".provisionprofile
   ```

   See [Create a Developer ID provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-developer-id-provisioning-profile/).
   WeatherKit needs this profile outside the App Store. The widget needs none: its sandbox and team-prefixed App Group are
   not restricted entitlements.
3. **Notarisation credentials in the keychain.** Make an app-specific password at account.apple.com › Sign-In and
   Security › App-Specific Passwords ([Apple's steps](https://support.apple.com/en-gb/102654)), then run this once and
   paste the password when it asks:

   ```bash
   xcrun notarytool store-credentials nightwatch-notary --apple-id YOUR_APPLE_ID_EMAIL --team-id 8B44CZ9923
   ```

   The password is kept in your keychain under the name `nightwatch-notary`; the script never sees it. (An App Store
   Connect API key works too: see [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).)

## Each release

1. Merge the release PR and tag it, as for every version: `git tag -a v0.6.6 -m "…" && git push origin v0.6.6`.
2. With the tag checked out and nothing uncommitted, run `scripts/release.sh --publish`. It:
   - builds the app and widget with `scripts/build-app.sh` (Xcode and xcodegen);
   - re-signs the widget, then the app, with the Developer ID, the hardened runtime and a secure timestamp, and embeds the
     Developer ID profile so WeatherKit works;
   - packages `build/release/Nightwatch-<version>.dmg` with an Applications shortcut, and signs it;
   - sends it to Apple's notary service and waits (usually a few minutes; on a rejection it prints Apple's log);
   - staples the ticket so the image opens offline, and checks it as Gatekeeper will: `accepted source=Notarized Developer ID`
     (the app copied out of it is covered by the same notarisation; opened for the first time with no network, macOS
     looks the ticket up when it next can);
   - writes the SHA-256 checksum beside it;
   - with `--publish`, attaches the DMG and checksum to the GitHub release for the tag, creating the release if needed,
     plus the same DMG as `Nightwatch.dmg` (with its own checksum), so
     `https://github.com/rsutcliffe/nightwatch/releases/latest/download/Nightwatch.dmg` always serves the newest version,
     with notes written by `scripts/release-notes.sh` from the version's row in the release history of
     `docs/product-overview.md`. Add that row before releasing: without it, `--publish` stops.
3. Point a website's download button at `https://github.com/rsutcliffe/nightwatch/releases/latest/download/Nightwatch.dmg` once; it then needs no change per release.

Without `--publish` the DMG stays in `build/release/`. `scripts/release.sh --skip-notarize` checks signing and packaging
without notarising; that image is for checking only, never for distribution.

## Before the first public release

- The data licences allow Nightwatch because it is free with no ads or in-app purchases (Open-Meteo, 7Timer, AuroraWatch
  UK, the Digitized Sky Survey). Keep it that way, or those sources need paid plans or replacing. See `NOTICE`.
- 7Timer asks developers to tell its author when they use the data.
- Downloads do not update themselves: people fetch each new version from the website or the GitHub release.
