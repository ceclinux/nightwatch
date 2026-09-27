#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
R=Sources/SkyCore/Resources
mkdir -p $R/catalog
curl -sSL -o $R/catalog/NGC.csv https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/NGC.csv
curl -sSL -o $R/catalog/addendum.csv https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/addendum.csv
curl -sSL -o $R/catalog/constellations.json https://raw.githubusercontent.com/ofrohn/d3-celestial/master/data/constellations.json
curl -sSL -o $R/catalog/constellations.lines.json https://raw.githubusercontent.com/ofrohn/d3-celestial/master/data/constellations.lines.json
head -1 $R/catalog/NGC.csv | cut -c1-60
wc -l $R/catalog/NGC.csv $R/catalog/addendum.csv
scripts/build-bright-stars.py
