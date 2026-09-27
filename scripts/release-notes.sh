#!/bin/zsh
# Prints the GitHub release notes for a version: "What's new", from that version's row in the product overview's release
# history (docs/product-overview.md), then how to install. release.sh --publish uses it; it fails when the row is missing,
# so a release cannot go out without its notes.
# With --appstore it prints the Mac App Store's "What's New in This Version" instead: plain text, no release name (the City
# Watch names stay on GitHub) and no install section. It fails over Apple's 4,000-character limit and warns about wording
# that only fits the download (GitHub, the DMG, the update check), which App Review can read against rule 2.3.10.
# usage: scripts/release-notes.sh [--appstore] <version>
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=github
[[ "${1:-}" == "--appstore" ]] && { MODE=appstore; shift }
python3 - "$MODE" "${1:?usage: scripts/release-notes.sh [--appstore] <version>}" <<'PY'
import re, sys
mode, v = sys.argv[1], sys.argv[2]
for line in open('docs/product-overview.md', encoding='utf-8'):
    cells = [c.strip() for c in line.strip().strip('|').split('|')]
    if len(cells) >= 4 and cells[0] == v:
        name, contents = cells[1], '|'.join(cells[3:])
        items = [i[0].upper() + i[1:] for i in (i.strip() for i in contents.split(';')) if i]
        if mode == 'appstore':
            text = '\n'.join(f'• {i.replace("`", "")}' for i in items)
            if len(text) > 4000:
                sys.exit(f'release-notes: {len(text)} characters; the App Store allows 4,000. Shorten the {v} row.')
            print(text)
            found = sorted({m.group(0).lower() for m in re.finditer(r'(?i)github|\bdmg\b|developer id|readme|download|update check|notaris', text)})
            if found:
                print(f'\nrelease-notes: edit before pasting; download-only wording: {", ".join(found)}', file=sys.stderr)
            sys.exit(0)
        print(f'## What\'s new in {v} "{name}"\n')
        for item in items: print(f'- {item}')
        print(f'''
## Install

Download `Nightwatch-{v}.dmg` below, open it and drag Nightwatch to Applications. It is signed with a Developer ID and notarised by Apple. The first time you open it, macOS asks whether to open an app downloaded from the internet: choose Open. Its SHA-256 checksum is in `Nightwatch-{v}.dmg.sha256`.

From 0.6.7 on, Nightwatch checks once a day for a newer version and says so in its popover. Questions and ideas: [Discussions](https://github.com/rsutcliffe/nightwatch/discussions). Problems: [Issues](https://github.com/rsutcliffe/nightwatch/issues).''')
        sys.exit(0)
sys.exit(f'release-notes: no row for {v} in the release history of docs/product-overview.md')
PY
