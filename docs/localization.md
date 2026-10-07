# Interface languages

Nightwatch supports English and Simplified Chinese (`zh-Hans`). Select **Settings → App → Language**, or use the
language picker on the first-run welcome screen. Options are **Follow System**, **English**, and **简体中文**.

- The selection takes effect immediately in the popover and all app windows. Changing language rebuilds view presentation
  state (for example, a selected target page or an open sheet may close), but keeps saved settings and favourites.
- `nightwatch.interfaceLanguage` in the app's UserDefaults persists the selection on this Mac. It is not part of the
  observing configuration and does not sync through iCloud. Unknown stored values fall back to Follow System.
- Follow System selects the first supported language in macOS's preferred-language list. Simplified Chinese includes
  `zh-Hans`, mainland China and Singapore; unsupported languages fall back to English. Traditional Chinese is not translated.
- Generated descriptions are recomputed from the cached primary forecast after switching. The language-change recomputation
  does not deliver notifications or advance notification state. Existing delivered notifications keep their old text.
- Signed builds include the resolved language in widget snapshots, so widget captions and stale-forecast messages agree with
  the app even though the widget runs in a different process. Older snapshots without this field still decode.
- Place names entered by the user, catalogue identifiers, telescope/filter brand names, star and constellation proper names,
  and external source names are retained. macOS permission dialogs follow the system's language; OS/network error descriptions
  and Siri/Shortcuts command metadata can still follow the system or remain English.

## Translation implementation

`Sources/SkyCore/Localization.swift` provides shared lookup and interpolation, used by the app, widget and generated copy.
English source text is the key and the fallback. `Sources/SkyCore/Resources/Localization/zh-Hans.json` holds Chinese values;
SwiftPM already copies the `Resources` directory into SkyCore's bundle, including in Xcode app builds.

```swift
Text(L10n.text("Settings"))
Text(L10n.format("Back to \(site.name)"))
```

The latter looks up `Back to {0}`. Numbered arguments can be reordered by translators. Values are substituted in a single
pass: user text such as `Home {1} 50%` is neither translated nor treated as another placeholder. Unknown keys use English.
For existing `String(format:)` call sites, translate the format string and keep every printf argument and its type intact.

**Never translate storage keys, raw enum values, resource paths, CSV headers or identifiers.** Canonical target type names
are also used by visibility and filter-selection rules; these remain English internally and are translated at presentation.
The tests cover catalogue identity, target classification, event identity, search, scoring and window invariance.

`InfoPlist.strings` under `Sources/Nightwatch/Resources/{en,zh-Hans}.lproj` supplies system-language location-permission copy.
These resources are included by the app's existing XcodeGen source folder.

## Verification

```sh
node scripts/check-localization.mjs
scripts/test.sh
```

The dependency-free Node check rejects duplicate keys, missing literal references, and changed numbered/printf placeholders.
`LocalizationTests.swift` covers language resolution, persistence, fallback, argument reordering, language switching, model
invariants and backwards-compatible widget snapshots. Task-local overrides keep these tests independent of other tests and
of the saved user preference. CI runs both the resource check and the test suite before building the app.

Manual acceptance on a Mac with a built application:

1. In the welcome screen, choose 简体中文; finish setup and reopen the app to verify persistence.
2. In 设置 → 应用 → 语言, select English, then 简体中文, then Follow System. Check already-open windows and the menu-bar popover.
3. Check settings pickers, tooltips, target/category search, detail pages, plan, week, dark sites, horizon/photo sheets,
   shooting tips, and the numbers guide. Try a site name containing braces, percent signs and Chinese characters.
4. Confirm dates change language but times remain in the observing site's time zone. Check Moon illumination and plan order.
5. On a signed build with widgets, switch the app language and wait for WidgetKit to reload. Verify all three widget sizes.
6. Check Standard/Large/Extra large text sizes for clipping. System dialogs and third-party content are not controlled by
   Nightwatch's in-app language picker.
