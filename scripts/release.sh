#!/bin/zsh
# Builds Nightwatch-<version>.dmg for download outside the App Store: signed with the Developer ID certificate, notarised
# by Apple and stapled, so it opens on any Mac without a warning. The one-off setup is in docs/releasing.md.
#
# usage: scripts/release.sh                 build, sign, notarise, staple and verify build/release/Nightwatch-<v>.dmg
#        scripts/release.sh --publish       then attach the DMG and its checksum to the GitHub release for tag v<version>
#        scripts/release.sh --skip-notarize check signing and packaging locally; the DMG is NOT for distribution
set -euo pipefail
cd "$(dirname "$0")/.."
PUBLISH=0; NOTARIZE=1
for a in "$@"; do
  case "$a" in
    --publish) PUBLISH=1 ;;
    --skip-notarize) NOTARIZE=0 ;;
    *) print -u2 "usage: scripts/release.sh [--publish | --skip-notarize]"; exit 2 ;;
  esac
done
(( PUBLISH && ! NOTARIZE )) && { print -u2 "release: --publish needs a notarised DMG; drop --skip-notarize"; exit 2 }
fail() { print -u2 "release: $1"; exit 1 }
NOTARY_PROFILE=${NIGHTWATCH_NOTARY_PROFILE:-nightwatch-notary}

# 1. Prerequisites (docs/releasing.md): the certificate, the app's Developer ID profile, the notarisation credentials.
IDENTITY=${NIGHTWATCH_RELEASE_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')}
[[ -n "$IDENTITY" ]] || fail "no 'Developer ID Application' certificate in the keychain (docs/releasing.md, step 1)"
# The team ID is the certificate's organisational unit. The bracket in the name is the team only on a Developer ID
# certificate; on a development one it is a personal ID.
# (Read from the name, not with openssl: macOS's own openssl prints the subject in a form the old parse missed.)
TEAM=${${IDENTITY##*\(}%\)}
(( ${#TEAM} == 10 )) || fail "could not read the team ID from the certificate '$IDENTITY'"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Sources/Nightwatch/Info.plist)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Nightwatch/Info.plist)
WIDGET_ID="$BUNDLE_ID.widget"
GROUP="$TEAM.$BUNDLE_ID"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# The app needs a Developer ID provisioning profile because WeatherKit is a restricted entitlement. A Developer ID profile
# is the one that provisions all devices. The widget's entitlements (sandbox, a team-prefixed App Group) need none.
PROFILE=""
for p in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.provisionprofile(N) ~/Library/MobileDevice/Provisioning\ Profiles/*.provisionprofile(N); do
  security cms -D -i "$p" > "$WORK/p.plist" 2>/dev/null || continue
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$WORK/p.plist" 2>/dev/null)" == "true" ]] || continue
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$WORK/p.plist" 2>/dev/null)" == "$TEAM.$BUNDLE_ID" ]] || continue
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.weatherkit' "$WORK/p.plist" 2>/dev/null)" == "true" ]] || continue
  PROFILE="$p"; break
done
if [[ -z "$PROFILE" ]]; then
  (( NOTARIZE )) && fail "no Developer ID provisioning profile with WeatherKit for $BUNDLE_ID (docs/releasing.md, step 2)"
  print "release: no Developer ID profile; continuing without WeatherKit because --skip-notarize"
fi
if (( NOTARIZE )); then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "no notarisation credentials named '$NOTARY_PROFILE' in the keychain (docs/releasing.md, step 3)"
fi
if (( PUBLISH )); then
  git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || fail "tag v$VERSION does not exist: tag the release first"
  # A published download must be built from exactly the tagged commit, with nothing uncommitted.
  [[ "$(git rev-parse "v$VERSION^{commit}")" == "$(git rev-parse HEAD)" ]] && git diff --quiet HEAD \
    || fail "check out v$VERSION with no uncommitted changes before publishing"
  command -v gh >/dev/null || fail "--publish needs the GitHub CLI (gh)"
  # The notes come from this version's row in the product overview's release history: no row, no release.
  scripts/release-notes.sh "$VERSION" > "$WORK/notes.md" || fail "add a $VERSION row to the release history in docs/product-overview.md first"
fi

# 2. Build with the everyday script (it embeds the widget), then re-sign both bundles with the Developer ID.
scripts/build-app.sh --no-install
SRC=build/Nightwatch.app
[[ -d "$SRC/Contents/PlugIns/NightwatchWidget.appex" ]] \
  || fail "the build has no widget: releases need Xcode, xcodegen and the Apple Development certificate and profile that build-app.sh uses (see build/xcode.log)"
OUT=build/release; mkdir -p "$OUT"
APP="$WORK/Nightwatch.app"
ditto "$SRC" "$APP"
APPEX="$APP/Contents/PlugIns/NightwatchWidget.appex"

cat > "$WORK/widget.entitlements" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
ENT
if [[ -n "$PROFILE" ]]; then
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  cat > "$WORK/app.entitlements" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.developer.weatherkit</key><true/>
  <key>com.apple.developer.ubiquity-kvstore-identifier</key><string>$TEAM.$BUNDLE_ID</string>
  <key>com.apple.application-identifier</key><string>$TEAM.$BUNDLE_ID</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM</string>
  <key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
  <key>com.apple.security.personal-information.location</key><true/>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key><array><string>/Library/Application Support/Nightwatch/</string><string>/Library/Caches/Nightwatch/</string></array>
  <key>com.apple.security.files.user-selected.read-only</key><true/>
</dict></plist>
ENT
else
  rm -f "$APP/Contents/embedded.provisionprofile"
  cat > "$WORK/app.entitlements" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
  <key>com.apple.security.personal-information.location</key><true/>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key><array><string>/Library/Application Support/Nightwatch/</string><string>/Library/Caches/Nightwatch/</string></array>
  <key>com.apple.security.files.user-selected.read-only</key><true/>
</dict></plist>
ENT
fi
# Inside out: the widget first, so the app's seal records the widget's new signature. Hardened runtime and a secure
# timestamp are both required for notarisation; the development build's get-task-allow is dropped by re-signing.
codesign --force --options runtime --timestamp --entitlements "$WORK/widget.entitlements" --sign "$IDENTITY" "$APPEX"
codesign --force --options runtime --timestamp --entitlements "$WORK/app.entitlements" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# 3. The disk image: the app beside an Applications shortcut, signed too.
DMG="$OUT/Nightwatch-$VERSION.dmg"
STAGE="$WORK/stage"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Nightwatch.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Nightwatch $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if (( ! NOTARIZE )); then
  print "Built $DMG, signed as $IDENTITY. NOT notarised: for checking locally only, not for distribution."
  exit 0
fi

# 4. Notarise (Apple checks it for malicious content; usually a few minutes), staple the ticket so it opens offline,
# then check it exactly as Gatekeeper will on someone else's Mac.
print "Submitting to Apple's notary service (this waits for the result)…"
# A rejection still exits 0; a network failure does not, and is reported by the status check below rather than by set -e.
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$WORK/notary.json" || true
STATUS=$(/usr/bin/plutil -extract status raw "$WORK/notary.json" 2>/dev/null || true)
if [[ "$STATUS" != "Accepted" ]]; then
  ID=$(/usr/bin/plutil -extract id raw "$WORK/notary.json" 2>/dev/null || true)
  [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" || true
  fail "notarisation was not accepted (status: ${STATUS:-unknown}); Apple's log is above"
fi
xcrun stapler staple -q "$DMG"
xcrun stapler validate -q "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
(cd "$OUT" && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
print "Ready: $DMG (notarised and stapled)"
print "SHA-256: $(cut -d' ' -f1 "$DMG.sha256")"

# 5. Optional: attach to the GitHub release for the tag, creating the release if it does not exist yet.
if (( PUBLISH )); then
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    gh release edit "v$VERSION" --notes-file "$WORK/notes.md" >/dev/null
  else
    gh release create "v$VERSION" --verify-tag --title "Nightwatch $VERSION" --notes-file "$WORK/notes.md" >/dev/null
  fi
  # The same DMG again under a name without the version, so a website can link to
  # releases/latest/download/Nightwatch.dmg and never change per release.
  cp "$DMG" "$OUT/Nightwatch.dmg"
  (cd "$OUT" && shasum -a 256 Nightwatch.dmg > Nightwatch.dmg.sha256)
  gh release upload "v$VERSION" "$DMG" "$DMG.sha256" "$OUT/Nightwatch.dmg" "$OUT/Nightwatch.dmg.sha256" --clobber
  print "Attached to https://github.com/rsutcliffe/nightwatch/releases/tag/v$VERSION"
fi
