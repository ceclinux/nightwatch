#!/usr/bin/env python3
"""Builds Sources/SkyCore/Resources/catalog/sharpless.csv and prints the Sharpless numbers of objects OpenNGC already has.

Sharpless's catalogue of H II regions (1959, 313 objects) is CDS/VizieR catalogue VII/20. Its positions are B1950 and are
turned to J2000 here. An object OpenNGC already lists under another name gets no row: where SIMBAD or OpenNGC says
which it is, its number is printed, for Catalog.sharplessNumbers; where an OpenNGC nebula merely lies inside the region
(the Orion Nebula inside Sh 2-281), the row is left out and the number is given by position: to the nebula nearest the
region's centre, printed apart for Catalog.sharplessByPosition, since that is a match and not an identification. Of the rest, a row is written for the
two brighter of Sharpless's three classes from 10 arcminutes to 5 degrees across (the Tulip, Sh 2-101, is class 2 and 20'),
in OpenNGC's columns, with no magnitude (he gives none). Names and the other catalogues' numbers are SIMBAD's.
Standard library only.

usage: scripts/build-sharpless.py catalog.dat simbad.tsv
  catalog.dat  https://vizier.cfa.harvard.edu/ftp/cats/VII/20/catalog.dat.gz, unpacked (any VizieR mirror)
  simbad.tsv   SIMBAD's TAP service, format=tsv, with the query
               SELECT i1.id AS sh, i2.id AS other FROM ident AS i1 JOIN ident AS i2 ON i1.oidref=i2.oidref
               WHERE i1.id LIKE 'SH  2-%' AND (i2.id LIKE 'NGC %' OR i2.id LIKE 'IC %' OR i2.id LIKE 'M %'
               OR i2.id LIKE 'NAME %' OR i2.id LIKE 'LBN %')
"""
import csv
import math
import pathlib
import re
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "Sources/SkyCore/Resources/catalog"
KEPT = {"PN", "HII", "EmN", "Neb", "RfN", "SNR", "DrkN", "Cl+N", "OCl", "*Ass"}   # what a Sharpless region can be in OpenNGC
GLOWING = {"PN", "HII", "EmN", "Neb", "RfN", "SNR", "Cl+N"}   # an OpenNGC object of these inside a region is that region, or part of it
MIN_CLASS, MIN_ARCMIN = 2, 10
MAX_ARCMIN = 300   # wider than this (Sh 2-27, 245, 310, 312: 8 to 12 degrees) no telescope here frames, and the survey shows only plate seams
# FK4 B1950 to FK5 J2000 (Standish 1982), without the E-terms: good to an arcsecond, against sizes in arcminutes.
B1950_TO_J2000 = ((0.9999256794956877, -0.0111814832204662, -0.0048590038153592),
                  (0.0111814832391717, 0.9999374848933135, -0.0000271625947142),
                  (0.0048590037723143, -0.0000271702937440, 0.9999881946023742))


def j2000(ra_h, dec_d):
    a, d = math.radians(ra_h * 15), math.radians(dec_d)
    v = (math.cos(d) * math.cos(a), math.cos(d) * math.sin(a), math.sin(d))
    x, y, z = (sum(m * c for m, c in zip(row, v)) for row in B1950_TO_J2000)
    return (math.degrees(math.atan2(y, x)) % 360) / 15, math.degrees(math.asin(z))


def hours(text):
    h, m, sec = (float(x) for x in text.lstrip("+-").split(":"))
    return (-1 if text.startswith("-") else 1) * (h + m / 60 + sec / 3600)


def separation_arcmin(ra1, dec1, ra2, dec2):
    a1, d1, a2, d2 = (math.radians(x) for x in (ra1 * 15, dec1, ra2 * 15, dec2))
    c = math.sin(d1) * math.sin(d2) + math.cos(d1) * math.cos(d2) * math.cos(a1 - a2)
    return math.degrees(math.acos(max(-1.0, min(1.0, c)))) * 60


def sexagesimal(value, sign=False):
    s = ("-" if value < 0 else "+") if sign else ""
    total = round(abs(value) * 3600, 1)
    return "%s%02d:%02d:%04.1f" % (s, total // 3600, total % 3600 // 60, total % 60)


def main(catalog_dat, simbad_tsv):
    others = {}   # Sharpless number -> SIMBAD's other identifiers
    for row in csv.reader(open(simbad_tsv), delimiter="\t"):
        m = re.fullmatch(r"SH +2-(\d+)", row[0])
        if m:
            others.setdefault(int(m.group(1)), []).append(" ".join(row[1].split()))

    glowing = []   # (name, RA hours, Dec degrees, radius in arcminutes)
    kinds, sizes = {}, {}   # OpenNGC name -> type, and width in arcminutes
    by_key, header = {}, None   # "NGC7000", "M8", "LBN 373", "SH 2-155" -> OpenNGC names
    for name in ("NGC", "addendum"):
        rows = csv.reader(open(CATALOG / f"{name}.csv"), delimiter=";")
        header = next(rows)
        col = {h: i for i, h in enumerate(header)}
        for r in rows:
            if r[col["Type"]] not in KEPT:
                continue
            keys = [r[col["Name"]]] + [t.strip() for t in r[col["Identifiers"]].split(",")]
            if r[col["M"]]:
                keys.append("M%d" % int(r[col["M"]]))
            for k in keys:
                by_key.setdefault(k, []).append(r[col["Name"]])
            if r[col["Type"]] in GLOWING and r[col["RA"]] and r[col["Dec"]]:
                glowing.append((r[col["Name"]], hours(r[col["RA"]]), hours(r[col["Dec"]]), float(r[col["MajAx"]] or 0) / 2))
                kinds[r[col["Name"]]], sizes[r[col["Name"]]] = r[col["Type"]], float(r[col["MajAx"]] or 0)

    def opengc(ident):
        m = re.fullmatch(r"(NGC|IC) (\d+)", ident)
        if m:
            return by_key.get("%s%04d" % (m.group(1), int(m.group(2))), [])
        m = re.fullmatch(r"M (\d+)", ident)
        if m:
            return by_key.get("M" + m.group(1), [])
        return by_key.get(ident, []) if re.fullmatch(r"LBN \d+", ident) else []

    aliases, new, inside, claims = {}, [], [], []
    for line in open(catalog_dat):
        n, diam, bright = int(line[0:4]), int(line[48:52]), int(line[54])
        ra = int(line[34:36]) + int(line[36:38]) / 60 + int(line[38:41]) / 36000
        dec = (-1 if line[41] == "-" else 1) * (int(line[42:44]) + int(line[44:46]) / 60 + int(line[46:48]) / 3600)
        ids = others.get(n, [])
        known = [x for i in ids for x in opengc(i)] + by_key.get("SH 2-%d" % n, [])
        for name in dict.fromkeys(known):
            aliases.setdefault(name, n)   # the first Sharpless number that names it
        if known:
            continue
        ra2000, dec2000 = j2000(ra, dec)
        near = sorted((separation_arcmin(ra2000, dec2000, g[1], g[2]), g[0]) for g in glowing
                      if separation_arcmin(ra2000, dec2000, g[1], g[2]) <= max(diam / 2, g[3]))
        # Any region SIMBAD does not identify, whatever its class. Not one wider than MAX_ARCMIN (Barnard's Loop, Sh 2-276, is 20
        # degrees: it is not the small nebula at its centre), nor a planetary or reflection nebula, which is no H II region, nor an
        # object over six times the region's width (Sh 2-192 is a 1' knot beside IC 1831).
        if diam <= MAX_ARCMIN:
            claims += [(sep, n, name) for sep, name in near if kinds[name] not in ("PN", "RfN") and sizes[name] <= 6 * diam]
        holds = [name for _, name in near]
        if bright < MIN_CLASS or diam < MIN_ARCMIN or diam > MAX_ARCMIN:
            continue
        if holds:
            inside.append("Sh 2-%d (%s)" % (n, ", ".join(holds[:3])))
            continue
        names = [i[5:] for i in ids if i.startswith("NAME ")]
        best = next((x for x in names if x.endswith("Nebula")), "")   # SIMBAD's other names can be a star's ("Alniyat" for Sh 2-9)
        lbn = [i for i in ids if re.fullmatch(r"LBN \d+", i)]
        row = dict.fromkeys(header, "")
        row.update({"Name": "Sh2-%d" % n, "Type": "HII", "RA": sexagesimal(ra2000), "Dec": sexagesimal(dec2000, sign=True),
                    "MajAx": "%.2f" % diam, "Identifiers": ",".join(["SH 2-%d" % n] + lbn), "Common names": best,
                    "Sources": "Sharpless 1959 (CDS/VizieR VII/20); names and identifiers from CDS/SIMBAD"})
        new.append([row[h] for h in header])

    with open(CATALOG / "sharpless.csv", "w", newline="") as f:
        w = csv.writer(f, delimiter=";", lineterminator="\n")
        w.writerow(header)
        w.writerows(new)
    # By position: the number goes to the OpenNGC nebula nearest the region's centre among those inside it. The nearest pairs are
    # settled first, an object keeps one number, and one SIMBAD or OpenNGC already identifies keeps that.
    by_position, numbered = {}, set()
    for sep, n, name in sorted(claims):
        if name not in aliases and name not in by_position and n not in numbered:
            by_position[name] = n
            numbered.add(n)
    print(f"{len(inside)} left out, an OpenNGC nebula lying inside each: " + "; ".join(inside))
    print(f"{len(by_position)} OpenNGC objects numbered by position:")
    print(", ".join('"%s": %d' % kv for kv in sorted(by_position.items(), key=lambda kv: kv[1])))
    print(f"{len(new)} new rows in sharpless.csv; {len(aliases)} OpenNGC objects with a Sharpless number:")
    items = sorted(aliases.items(), key=lambda kv: kv[1])
    print(", ".join('"%s": %d' % kv for kv in items))


if __name__ == "__main__":
    main(*sys.argv[1:3])
