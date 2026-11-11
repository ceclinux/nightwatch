#!/bin/zsh
# Build for a simulator, launch the demo and screenshot it: scripts/shot.sh "iPad Air 11-inch (M4)" out.png [red]
set -e
cd "${0:A:h}/.."
NAME=$1 OUT=$2 RED=${3:-} EXTRA=${4:-}
UDID=$(xcrun simctl list devices available | grep -F "$NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild -project NightwatchPhone.xcodeproj -scheme NightwatchPhone -destination "platform=iOS Simulator,name=$NAME" CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd -jobs 3 build -quiet >/dev/null
xcrun simctl boot $UDID 2>/dev/null || true
xcrun simctl bootstatus $UDID -b >/dev/null
xcrun simctl install $UDID "$(find build/dd -name Nightwatch.app -path '*iphonesimulator*' | head -1)"
xcrun simctl terminate $UDID io.github.rsutcliffe.nightwatch 2>/dev/null || true
ARGS=(-demo ${=EXTRA}); [[ -n $RED ]] && ARGS+=(-redNightMode YES) || ARGS+=(-redNightMode NO)
xcrun simctl launch $UDID io.github.rsutcliffe.nightwatch $ARGS >/dev/null
sleep ${SHOT_WAIT:-10}
xcrun simctl io $UDID screenshot "$OUT" >/dev/null
