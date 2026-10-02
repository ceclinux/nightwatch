#!/bin/zsh
# Imports the event artwork (v1.0.1) into Resources/Events as <name>.heic: 512 px, HEIC at quality 80 with transparency,
# as scripts/import-constellations.sh does for the constellations.
# usage: scripts/import-event-art.sh <folder holding the nightwatch-*.png artwork>
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:?usage: scripts/import-event-art.sh <artwork folder>}"
OUT=Resources/Events
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
for pair in meteor-showers:nightwatch-meteor-showers comets:nightwatch-comets conjunctions:nightwatch-conjunctions \
            solar-eclipse:nightwatch-eclipses lunar-eclipse:nightwatch-lunar-eclipse iss:nightwatch-international-space-station \
            clear-sky:nightwatch-clear-sky-tonight occultation:nightwatch-occultation \
            milky-way-core:nightwatch-milky-way milky-way-cygnus:nightwatch-milky-way-cygnus; do
  name=${pair%%:*}; file=${pair#*:}
  sips -Z 512 "$SRC/$file.png" --out "$TMP/$name.png" >/dev/null
  sips -s format heic -s formatOptions 80 "$TMP/$name.png" --out "$OUT/$name.heic" >/dev/null
done
echo "Imported $(ls "$OUT"/*.heic | wc -l | tr -d ' ') pictures into $OUT ($(du -sh "$OUT" | cut -f1))"
