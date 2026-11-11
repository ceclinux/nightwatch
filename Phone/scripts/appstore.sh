#!/bin/zsh
# Builds the iPhone and iPad App Store package, build/appstore-ios/Nightwatch-<version>.ipa: Release archive of the phone app and its
# widget, exported for App Store Connect with the Apple Distribution certificate and the two iOS App Store profiles, then checked
# (entitlements, privacy manifests, encryption flag, quarantine). Upload it with Apple's Transporter app. The Mac's version of this
# is scripts/appstore.sh; the runbook is docs/app-store.md and Phone/docs/app-store.md.
#
# It never lets Xcode touch the developer account: no -allowProvisioningUpdates, because the app and widget IDs are the Mac's
# and a signed build that adds a capability to an App ID invalidates the Mac's profiles (26 Oct 2026).
#
# usage: Phone/scripts/appstore.sh [--check]     (--check stops after the prerequisites)
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { print -u2 "appstore-ios: $1"; exit 1 }

# 1. Prerequisites: an Apple Distribution certificate, and an iOS App Store profile for the app and for the widget.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Distribution/{print $2; exit}')
[[ -n "$IDENTITY" ]] || fail "no 'Apple Distribution' certificate in the keychain (docs/app-store.md, step 2)"
TEAM=${${IDENTITY##*\(}%\)}
(( ${#TEAM} == 10 )) || fail "could not read the team ID from the certificate '$IDENTITY'"
SPEC=Phone/project.yml
BUNDLE_ID=$(awk '/PRODUCT_BUNDLE_IDENTIFIER:/{print $2; exit}' $SPEC)
WIDGET_ID=$(awk '/PRODUCT_BUNDLE_IDENTIFIER:/{n++; if (n==2) {print $2; exit}}' $SPEC)
VERSION=$(awk '/MARKETING_VERSION:/{gsub(/"/,"",$2); print $2; exit}' $SPEC)
BUILD=$(awk '/CURRENT_PROJECT_VERSION:/{gsub(/"/,"",$2); print $2; exit}' $SPEC)
GROUP=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' Phone/App/Nightwatch.entitlements)
[[ "$BUNDLE_ID" == io.github.rsutcliffe.nightwatch && "$WIDGET_ID" == "$BUNDLE_ID.widget" ]] || fail "Phone/project.yml does not carry the Mac's bundle IDs (read '$BUNDLE_ID' and '$WIDGET_ID')"
[[ -n "$VERSION" && -n "$BUILD" && -n "$GROUP" ]] || fail "could not read the version, build or App Group"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
pl() { /usr/libexec/PlistBuddy -c "Print :$1" "$WORK/p.plist" 2>/dev/null }

# An iOS App Store profile names the bundle, provisions no devices (that would be development or ad hoc), is not an enterprise
# profile, and has not expired. Prints its name.
store_profile() {
  local p
  for p in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.(mobileprovision|provisionprofile)(N) ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision(N); do
    security cms -D -i "$p" > "$WORK/p.plist" 2>/dev/null || continue
    [[ "$(pl Platform:0)" == iOS ]] || continue
    [[ "$(pl Entitlements:application-identifier)" == "$TEAM.$1" ]] || continue
    pl ProvisionedDevices >/dev/null && continue
    pl ProvisionsAllDevices >/dev/null && continue
    [[ "$(pl Entitlements:get-task-allow)" == false ]] || continue
    local expires; expires=$(pl ExpirationDate) || continue
    (( $(date -j -f "%a %b %d %T %Z %Y" "$expires" +%s 2>/dev/null || echo 0) > $(date +%s) )) || continue   # expired
    pl Name; return
  done
}
APP_PROFILE=$(store_profile "$BUNDLE_ID"); WIDGET_PROFILE=$(store_profile "$WIDGET_ID")
[[ -n "$APP_PROFILE" ]] || fail "no iOS App Store profile for $BUNDLE_ID in ~/Library/Developer/Xcode/UserData/Provisioning Profiles (Phone/docs/app-store.md, 'Signing')"
[[ -n "$WIDGET_PROFILE" ]] || fail "no iOS App Store profile for $WIDGET_ID in ~/Library/Developer/Xcode/UserData/Provisioning Profiles (Phone/docs/app-store.md, 'Signing')"
print "Signing $BUNDLE_ID $VERSION ($BUILD) with '$IDENTITY'; profiles '$APP_PROFILE' and '$WIDGET_PROFILE'"
[[ "${1:-}" == --check ]] && { print "Prerequisites are in place."; exit 0 }

# 2. Archive (development-signed, which is how an archive is made), then export with the distribution profiles.
xcodegen generate --spec Phone/project.yml >/dev/null
ARCHIVE="$WORK/Nightwatch.xcarchive"
xcodebuild -project Phone/NightwatchPhone.xcodeproj -scheme NightwatchPhone -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -jobs 2 archive -quiet || fail "the archive failed"
cat > "$WORK/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>provisioningProfiles</key><dict>
    <key>$BUNDLE_ID</key><string>$APP_PROFILE</string>
    <key>$WIDGET_ID</key><string>$WIDGET_PROFILE</string>
  </dict>
</dict></plist>
PLIST
EXPORT="$WORK/export"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$WORK/export.plist" -quiet || fail "the export failed"
IPA=$(print -l "$EXPORT"/*.ipa(N) | head -1)
[[ -f "$IPA" ]] || fail "the export wrote no .ipa"

# 3. Check what was built, as the Mac script does: App Store Connect only tells you after upload.
unzip -q "$IPA" -d "$WORK/ipa"
APP="$WORK/ipa/Payload/Nightwatch.app"; APPEX="$APP/PlugIns/NightwatchWidget.appex"
[[ -d "$APP" && -d "$APPEX" ]] || fail "the package has no app or no widget"
codesign --verify --deep --strict "$APP" || fail "the signature does not verify"
ent() { codesign -d --entitlements - --xml "$1" 2>/dev/null > "$WORK/e.plist"; /usr/libexec/PlistBuddy -c "Print :$2" "$WORK/e.plist" 2>/dev/null }
[[ "$(ent "$APP" com.apple.developer.weatherkit)" == true ]] || fail "the app lacks the WeatherKit entitlement"
[[ "$(ent "$APP" com.apple.developer.ubiquity-kvstore-identifier)" == "$TEAM.$BUNDLE_ID" ]] || fail "the app's key-value store identifier is not $TEAM.$BUNDLE_ID"
[[ "$(ent "$APP" com.apple.security.application-groups:0)" == "$GROUP" ]] || fail "the app's App Group is not $GROUP"
[[ "$(ent "$APPEX" com.apple.security.application-groups:0)" == "$GROUP" ]] || fail "the widget's App Group is not $GROUP"
for b in "$APP" "$APPEX"; do
  [[ "$(ent "$b" get-task-allow)" != true ]] || fail "$b carries the debugging entitlement"
  [[ -f "$b/PrivacyInfo.xcprivacy" ]] || fail "$b has no privacy manifest"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$b/Info.plist")" == "$VERSION" ]] || fail "$b is not version $VERSION"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$b/Info.plist")" == "$BUILD" ]] || fail "$b is not build $BUILD"
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$APP/Info.plist")" == false ]] || fail "ITSAppUsesNonExemptEncryption is not false"
[[ "$(xattr -r "$WORK/ipa" 2>/dev/null)" != *com.apple.quarantine* ]] || fail "a file in the package is quarantined, which App Store Connect rejects (error 91109)"

mkdir -p build/appstore-ios
OUT="build/appstore-ios/Nightwatch-$VERSION-$BUILD.ipa"
cp "$IPA" "$OUT"
print "Built $OUT ($(du -h "$OUT" | cut -f1)). Upload it with Apple's Transporter app: open -a Transporter \"$OUT\""
