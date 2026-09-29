#!/bin/zsh
# Builds the Mac App Store package, build/appstore/Nightwatch-<version>.pkg: the APPSTORE variant of the same code (no
# update check, Sources/Nightwatch/Distribution.swift), signed with the Apple Distribution certificate and the two Mac App
# Store profiles, packaged and signed for upload with Apple's Transporter app. The one-off setup is in docs/app-store.md.
#
# usage: scripts/appstore.sh
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { print -u2 "appstore: $1"; exit 1 }

# 1. Prerequisites (docs/app-store.md): two certificates and a Mac App Store profile for the app and for the widget.
IDENTITY=${NIGHTWATCH_APPSTORE_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Distribution/{print $2; exit}')}
[[ -n "$IDENTITY" ]] || fail "no 'Apple Distribution' certificate in the keychain (docs/app-store.md, step 1)"
INSTALLER=${NIGHTWATCH_INSTALLER_IDENTITY:-$(security find-identity -v -p basic | awk -F'"' '/3rd Party Mac Developer Installer|Mac Installer Distribution/{print $2; exit}')}
[[ -n "$INSTALLER" ]] || fail "no 'Mac Installer Distribution' certificate in the keychain (docs/app-store.md, step 1)"
# The team ID is the bracket in a distribution certificate's name (macOS's own openssl prints subjects differently).
TEAM=${${IDENTITY##*\(}%\)}
(( ${#TEAM} == 10 )) || fail "could not read the team ID from the certificate '$IDENTITY'"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Sources/Nightwatch/Info.plist)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Nightwatch/Info.plist)
WIDGET_ID="$BUNDLE_ID.widget"
GROUP="$TEAM.$BUNDLE_ID"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# A Mac App Store profile names the bundle, provisions no devices and is not Developer ID (which provisions all devices).
store_profile() {
  for p in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.provisionprofile(N) ~/Library/MobileDevice/Provisioning\ Profiles/*.provisionprofile(N); do
    security cms -D -i "$p" > "$WORK/p.plist" 2>/dev/null || continue
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$WORK/p.plist" 2>/dev/null)" == "$TEAM.$1" ]] || continue
    /usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$WORK/p.plist" >/dev/null 2>&1 && continue
    /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$WORK/p.plist" >/dev/null 2>&1 && continue
    expires=$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$WORK/p.plist" 2>/dev/null) || continue
    (( $(date -j -f "%a %b %d %T %Z %Y" "$expires" +%s 2>/dev/null || echo 0) > $(date +%s) )) || continue   # expired
    print -r -- "$p"; return
  done
}
APP_PROFILE=$(store_profile "$BUNDLE_ID"); WIDGET_PROFILE=$(store_profile "$WIDGET_ID")
[[ -n "$APP_PROFILE" ]] || fail "no Mac App Store profile for $BUNDLE_ID (docs/app-store.md, step 3)"
[[ -n "$WIDGET_PROFILE" ]] || fail "no Mac App Store profile for $WIDGET_ID (docs/app-store.md, step 3)"

# 2. Build the App Store variant with the everyday script, then re-sign both bundles for the store.
NIGHTWATCH_APPSTORE=1 scripts/build-app.sh --no-install
SRC=build/Nightwatch.app
[[ -d "$SRC/Contents/PlugIns/NightwatchWidget.appex" ]] \
  || fail "the build has no widget: it needs Xcode, xcodegen and the Apple Development certificate and profile (docs/app-store.md, before you start)"
OUT=build/appstore; mkdir -p "$OUT"
APP="$WORK/Nightwatch.app"; ditto "$SRC" "$APP"
APPEX="$APP/Contents/PlugIns/NightwatchWidget.appex"
cp "$APP_PROFILE" "$APP/Contents/embedded.provisionprofile"
cp "$WIDGET_PROFILE" "$APPEX/Contents/embedded.provisionprofile"
# A downloaded profile is quarantined, and its copy is too (even with cp -X, on macOS 27). App Store Connect rejects a
# quarantined file anywhere in the app (error 91109), so strip it before signing; step 3 checks it has gone.
xattr -dr com.apple.quarantine "$APP"

# The store build's entitlements are the everyday build's, minus the temporary sandbox exceptions (they exist only to copy
# 0.6 settings, which a new App Store user never had) and minus Xcode's debugging entitlement on the widget. Derived rather
# than written out again, so the two builds cannot drift apart.
store_entitlements() {   # bundle, output file
  codesign -d --entitlements - --xml "$1" > "$2" 2>/dev/null || fail "could not read the entitlements of $1"
  for k in com.apple.security.temporary-exception.files.home-relative-path.read-only com.apple.security.get-task-allow; do
    /usr/libexec/PlistBuddy -c "Delete :$k" "$2" >/dev/null 2>&1 || true
  done
}
store_entitlements "$APP" "$WORK/app.entitlements"
store_entitlements "$APPEX" "$WORK/widget.entitlements"
for k in com.apple.application-identifier:"$TEAM.$WIDGET_ID" com.apple.developer.team-identifier:"$TEAM"; do   # the widget must name itself
  /usr/libexec/PlistBuddy -c "Delete :${k%%:*}" "$WORK/widget.entitlements" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :${k%%:*} string ${k#*:}" "$WORK/widget.entitlements"
done
# The app and the widget each carry the SkyCore package's resource bundle with the same identifier, which App Store Connect rejects
# as a collision. Bundle.module finds the bundle by name, not identifier, so each gets its own.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID.resources" "$APP/Contents/Resources/Nightwatch_SkyCore.bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $WIDGET_ID.resources" "$APPEX/Contents/Resources/Nightwatch_SkyCore.bundle/Contents/Info.plist"
# Inside out: the widget first, so the app's seal records the widget's new signature.
codesign --force --options runtime --entitlements "$WORK/widget.entitlements" --sign "$IDENTITY" "$APPEX"
codesign --force --options runtime --entitlements "$WORK/app.entitlements" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# 3. Guard the difference between the builds before packaging.
# No pipes here: under pipefail a grep that stops at the first match can make the check pass silently.
for b in "$APP" "$APPEX"; do
  ents=$(codesign -d --entitlements - --xml "$b" 2>/dev/null)
  [[ "$ents" == *temporary-exception* ]] && fail "the store build must carry no temporary sandbox exception ($b)"
done
attrs=$(xattr -r "$APP" 2>/dev/null)
[[ "$attrs" == *com.apple.quarantine* ]] && fail "a file in the store build is quarantined, which App Store Connect rejects (error 91109)"
grep -qaF "Check for a new version once a day" "$APP/Contents/MacOS/Nightwatch" && fail "the store build still has the update check: was it built with the APPSTORE condition?"
sdk=$(vtool -show-build "$APP/Contents/MacOS/Nightwatch" | awk '/ sdk /{print $2; exit}')
(( ${sdk%%.*} >= 26 )) || fail "the app records macOS SDK $sdk; App Store Connect needs 26 or later"

# 4. Package for upload.
PKG="$OUT/Nightwatch-$VERSION.pkg"
# On macOS 27 productbuild prints "write: Permission denied" a few times and still writes a valid, signed package
# (seen on 26 September 2026; the same in other projects). The check below is what matters.
productbuild --component "$APP" /Applications --sign "$INSTALLER" "$PKG"
pkgutil --check-signature "$PKG" >/dev/null || fail "the package signature does not verify"
print "Ready: $PKG (version $VERSION, build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"))"
print "Upload it with Apple's Transporter app: open -a Transporter \"$PKG\""
