#!/usr/bin/env python3
"""Checks the published survey picture set the way the app reads it, and that the app's numbers for every listed target find a picture in it.

    python3 scripts/verify-survey-pack.py [--file build/survey-set.nwsp]   (default: download the published release asset)

Written 3 November 2026. Layout: Sources/SkyCore/SurveyPack.swift. Needs Pillow only to open each picture. Exit 1 on any failure.
"""
import argparse, csv, hashlib, io, json, sys, urllib.request
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
URL = "https://github.com/rsutcliffe/nightwatch/releases/download/survey-set-1/survey-set.nwsp"
sys.path.insert(0, str(ROOT / "scripts"))
import importlib.util
spec = importlib.util.spec_from_file_location("build_survey_set", ROOT / "scripts/build-survey-set.py")
bss = importlib.util.module_from_spec(spec); spec.loader.exec_module(bss)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--file")
    a = ap.parse_args()
    data = Path(a.file).read_bytes() if a.file else urllib.request.urlopen(urllib.request.Request(URL, headers={"User-Agent": "Nightwatch-verify/1"}), timeout=120).read()
    bad = []
    if data[:8] != b"NWSURV1\n": print("FAIL: not a pack"); sys.exit(1)
    n = int.from_bytes(data[8:12], "little"); entries = json.loads(data[12:12 + n])["entries"]; base = 12 + n
    print(f"{len(data)} bytes, sha256 {hashlib.sha256(data).hexdigest()[:16]}, {len(entries)} entries")
    for key, (off, length) in entries.items():
        if base + off + length > len(data): bad.append(("outside the file", key)); continue
        try:
            im = Image.open(io.BytesIO(data[base + off:base + off + length])); im.load()
            if im.size != (480, 274): bad.append((f"size {im.size}", key))
        except Exception as e:
            bad.append((f"unreadable: {e}", key))
    missing = [t["id"] for t in bss.targets() if bss.card_key(t) not in entries]
    print(f"targets the app lists: {len(bss.targets())}, without a picture: {len(missing)} {missing[:5]}")
    for why, key in bad[:10]: print("FAIL", why, key)
    sys.exit(1 if bad or missing else 0)


if __name__ == "__main__":
    main()
