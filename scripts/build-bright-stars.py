#!/usr/bin/env python3
"""Builds Sources/SkyCore/Resources/stars/bright.json: the named stars of magnitude 2.0 or brighter (49 of them), from
d3-celestial's star catalogue and star names (BSD-3-Clause, credited in NOTICE). Standard library only.

usage: scripts/build-bright-stars.py
"""
import json
import pathlib
import urllib.request

BASE = "https://raw.githubusercontent.com/ofrohn/d3-celestial/master/data/"
LIMIT = 2.0
OUT = pathlib.Path(__file__).resolve().parent.parent / "Sources/SkyCore/Resources/stars/bright.json"


def fetch(name):
    with urllib.request.urlopen(BASE + name, timeout=60) as r:
        return json.load(r)


stars = fetch("stars.6.json")["features"]
names = fetch("starnames.json")
out = []
for f in stars:
    n = names.get(str(f["id"]), {})
    mag = f["properties"]["mag"]
    if not n.get("name") or mag > LIMIT:
        continue
    ra, dec = f["geometry"]["coordinates"]   # d3-celestial: RA in degrees from -180 to 180
    out.append({
        "id": f"HIP{f['id']}",
        "name": n["name"],
        "designation": f"{n.get('desig', '')} {n.get('c', '')}".strip(),
        "magnitude": mag,
        "raHours": round((ra % 360) / 15, 5),
        "decDeg": round(dec, 4),
    })
out.sort(key=lambda s: s["magnitude"])
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(out, ensure_ascii=False, indent=0) + "\n", encoding="utf-8")
print(f"{len(out)} stars to magnitude {LIMIT} -> {OUT}")
