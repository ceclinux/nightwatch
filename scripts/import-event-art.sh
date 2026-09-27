#!/bin/zsh
# Imports the event artwork (v1.0.1) into Resources/Events as <name>.heic: 512 px, HEIC at quality 80 with transparency,
# as scripts/import-constellations.sh does for the constellations. The owner's own full Moon (docs/images/moon-dwarf-mini.jpg,
# already stripped of its location) is cropped square for lunar eclipses.
# usage: scripts/import-event-art.sh <folder holding the nightwatch-*.png artwork>
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:?usage: scripts/import-event-art.sh <artwork folder>}"
OUT=Resources/Events
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
for pair in meteor-showers:nightwatch-meteor-showers comets:nightwatch-comets conjunctions:nightwatch-conjunctions \
            solar-eclipse:nightwatch-eclipses iss:nightwatch-international-space-station clear-sky:nightwatch-clear-sky-tonight; do
  name=${pair%%:*}; file=${pair#*:}
  sips -Z 512 "$SRC/$file.png" --out "$TMP/$name.png" >/dev/null
  sips -s format heic -s formatOptions 80 "$TMP/$name.png" --out "$OUT/$name.heic" >/dev/null
done
# The Moon fills the middle of a 16:9 frame: crop the centre square, then size it like the rest.
M=docs/images/moon-dwarf-mini.jpg
h=$(sips -g pixelHeight "$M" | awk '/pixelHeight/{print $2}')
sips -c "$h" "$h" "$M" --out "$TMP/moon.jpg" >/dev/null
sips -Z 512 -s format heic -s formatOptions 80 "$TMP/moon.jpg" --out "$OUT/lunar-eclipse.heic" >/dev/null
echo "Imported $(ls "$OUT"/*.heic | wc -l | tr -d ' ') pictures into $OUT ($(du -sh "$OUT" | cut -f1))"
