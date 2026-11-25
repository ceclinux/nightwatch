# Releasing Nightwatch for download

A release is a disk image, `Nightwatch-<version>.dmg`, signed with a Developer ID certificate and notarised by Apple, so it
opens on anyone's Mac without a security warning. `scripts/release.sh` does the whole job; the one-off setup below comes
first. Nightwatch is not sandboxed, so it cannot go on the Mac App Store as it stands; this is the route for a download
from a website or a GitHub release.

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

## The survey picture set

Target pictures normally come from CDS's hips2fits. CDS was unreachable for days from 26 October 2026 and every card fell back to its icon, so the
app also carries a pre-built set: one 480 x 274 colour DSS2 picture for each of the 2,080 targets the app can list (1,948 from OpenNGC, and 83 Sharpless nebulae and the 49 named stars, both added 25 November 2026), in the default 2.1 x 1.2
degree field of view. It is one file, `survey-set.nwsp` (layout in `Sources/SkyCore/SurveyPack.swift`), published as an asset of the prerelease tagged
`survey-set-1`. The app fetches it once, on the first card that wants a picture, and keeps it in the caches folder; `SurveyFetch` looks in it before
CDS. When CDS cannot be reached, a target outside the set shows its icon: a greyscale NASA SkyView stand-in shipped in 1.7.2 and 1.0.1 and was removed in 1.7.3 and 1.0.2, because on a target's page the large grey picture replaced the colour card picture.

**It is a prerelease on purpose.** GitHub's "latest release" is what the update check and the disk image link read; a data release must never be it.

Rebuild it (only when the catalogue's target list or the default field of view changes; the pictures themselves do not age):

```bash
python3 -m venv build/survey-venv && build/survey-venv/bin/pip install numpy astropy-healpix pillow
build/survey-venv/bin/python scripts/build-survey-set.py --source hips --out build/survey-set-colour --pack build/survey-set.nwsp
```

`--source hips` cuts the pictures from the HiPS tiles of the DSS2 colour survey on two public mirrors (IRSA at Caltech and CASDA at CSIRO), one
request at a time, alternating, with the tiles kept in `build/hips-tiles`. `--source cds` asks hips2fits instead when it is up. Publish with
`gh release create survey-set-1 build/survey-set.nwsp --prerelease --latest=false --title "Survey picture set" --notes-file <notes>`, or, for a
new set under the same tag, `gh release upload survey-set-1 build/survey-set.nwsp --clobber`. When a new set adds targets, also raise the number in `SurveyPackStore.fileName` (`Sources/SkyCore/SurveyPack.swift`) and add the old name to `earlierFileNames`: the app never fetches a set it already holds, so without that only new installs get the new pictures. The credit (Digitized Sky Survey, STScI/NASA, plate
owners, CDS) is in the app's About page and the notes, and the notes say the set is offered under the Open Database License 1.0 (CDS asked for
this on 3 November 2026: its HiPS are ODbL share-alike, and the original producers' terms take precedence).
