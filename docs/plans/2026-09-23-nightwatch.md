# Nightwatch Implementation Plan

**Goal:** A silent macOS menu-bar app that notifies when tonight is clear enough for a multi-hour imaging session and lists what to observe, grouped by phenomenon with thumbnails.

**Architecture:** One SwiftPM package. `SkyCore` (pure logic: forecast, ephemeris, catalogue, events, planner, alert state machine, settings) is fully unit-tested against fixtures and oracles. `Nightwatch` (SwiftUI `MenuBarExtra`, no Dock icon) wires a 30-minute scheduler, CoreLocation, notifications and views on top. Astronomy Engine is vendored as a C target; SatelliteKit is the one external Swift dependency.

**Tech Stack:** Swift 6.4 toolchain via Command Line Tools (no Xcode), SwiftPM, SwiftUI, Swift Testing, Astronomy Engine (C, MIT), SatelliteKit 2.1.2 (MIT), Open-Meteo, 7Timer ASTRO, OpenNGC, d3-celestial constellation GeoJSON, CDS hips2fits, MPC comet elements, CelesTrak TLE.

**Spec:** `docs/specs/2026-09-23-nightwatch-design.md`

## Global Constraints

- macOS 14 minimum; build with `swift build -c release`; no Xcode, no WidgetKit, no Apple Developer account.
- Tests run through `scripts/test.sh`, which passes `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` when that directory exists. XCTest is unavailable on this toolchain; use `import Testing`.
- No API keys anywhere. Sources: Open-Meteo, 7Timer ASTRO, hips2fits `CDS/P/DSS2/color`, MPC `cometels.json.gz`, CelesTrak `gp.php?CATNR=25544&FORMAT=TLE`.
- Every "evening" or "night" boundary comes from the ephemeris at the site's latitude, longitude and time zone. The only fixed clock hours are the user's quiet hours.
- Go rule defaults: `minHours = 3`, `maxCloudPct = 25`, `minAltitudeDeg = 30`. Alerts: heads-up at sunset − 60 min, go at window start − 30 min, cancel on downgrade, quiet hours 00:00–07:00 local, no alert when forecast older than 6 h.
- Licence MIT. Data attributions listed in `NOTICE` and the About window.
- Discworld flavour: only the strings in the `Copy` table (spec §6). Every flavoured string must read as ordinary English. `flavour: "plain"` swaps them.
- Bundle id `io.github.rsutcliffe.nightwatch`. App name `Nightwatch`.
- Commit after every task with a conventional message. No commit message contains "time-boxed", "deferred" or "partial".

---

## File Structure

```
Package.swift
LICENSE                                   MIT
NOTICE                                    data attributions
README.md
.gitignore
scripts/test.sh                           swift test with the Testing plugin path
scripts/fetch-data.sh                     downloads catalogue and constellation data into Resources
scripts/build-app.sh                      assembles, signs and installs Nightwatch.app
Sources/CAstronomyEngine/include/astronomy.h   vendored, MIT
Sources/CAstronomyEngine/astronomy.c
Sources/SkyCore/Time.swift                Date <-> astro_time_t
Sources/SkyCore/Site.swift                Site
Sources/SkyCore/Ephemeris.swift           Night, MoonState, BodyPosition, altAz, eclipses, constellation lookup
Sources/SkyCore/Forecast.swift            HourlyConditions, Forecast, Fetcher, OpenMeteo, SevenTimer, ForecastService
Sources/SkyCore/Catalog.swift             DeepSkyObject, TargetGroup, Catalog, Constellations
Sources/SkyCore/Planner.swift             GoRule, FieldOfView, ClearWindow, NightPlan, RankedTarget, Planner
Sources/SkyCore/Events.swift              MeteorShower, SkyEvent, Events (showers, eclipses, conjunctions)
Sources/SkyCore/Comets.swift              CometElements, Comets
Sources/SkyCore/Satellites.swift          TLE, SatellitePass, Satellites
Sources/SkyCore/Alerts.swift              AlertSettings, AlertState, AlertNotification, AlertEngine
Sources/SkyCore/Copy.swift                Flavour, Copy
Sources/SkyCore/Config.swift              Config, ConfigStore, TelescopePreset
Sources/SkyCore/Resources/catalog/NGC.csv, addendum.csv           (fetched by script)
Sources/SkyCore/Resources/catalog/constellations.json, constellations.lines.json
Sources/SkyCore/Resources/events/meteor-showers.json
Sources/SkyCore/Resources/presets/telescopes.json
Sources/Nightwatch/NightwatchApp.swift    @main, MenuBarExtra, windows
Sources/Nightwatch/Store.swift            state, cache, refresh pipeline
Sources/Nightwatch/Scheduler.swift        NSBackgroundActivityScheduler + wake observer
Sources/Nightwatch/LocationProvider.swift CoreLocation
Sources/Nightwatch/Notifier.swift         UNUserNotificationCenter
Sources/Nightwatch/Thumbnails.swift       hips2fits cache
Sources/Nightwatch/Views/TonightView.swift
Sources/Nightwatch/Views/TargetsView.swift
Sources/Nightwatch/Views/DetailView.swift
Sources/Nightwatch/Views/SettingsView.swift
Sources/Nightwatch/Views/AboutView.swift
Sources/Nightwatch/Views/Theme.swift      colours, glyphs
Sources/Nightwatch/Info.plist             template copied by build-app.sh
Tests/SkyCoreTests/*.swift
Tests/SkyCoreTests/Fixtures/openmeteo.json, seventimer.json, iss.tle, comets.json, ngc-sample.csv
```

---

### Task 1: Package scaffold, vendored Astronomy Engine, test script

**Files:**
- Create: `Package.swift`, `LICENSE`, `NOTICE`, `README.md`, `.gitignore`, `scripts/test.sh`
- Create: `Sources/CAstronomyEngine/include/astronomy.h`, `Sources/CAstronomyEngine/astronomy.c` (downloaded)
- Create: `Sources/SkyCore/Time.swift`, `Sources/Nightwatch/NightwatchApp.swift` (placeholder that compiles)
- Test: `Tests/SkyCoreTests/TimeTests.swift`

**Interfaces:**
- Produces: `extension astro_time_t { init(_ date: Date); var date: Date }` in `SkyCore` (internal), module `CAstronomyEngine` importable from `SkyCore`.

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nightwatch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SkyCore", targets: ["SkyCore"]),
        .executable(name: "Nightwatch", targets: ["Nightwatch"])
    ],
    dependencies: [
        .package(url: "https://github.com/gavineadie/SatelliteKit.git", exact: "2.1.2")
    ],
    targets: [
        .target(name: "CAstronomyEngine", path: "Sources/CAstronomyEngine"),
        .target(
            name: "SkyCore",
            dependencies: ["CAstronomyEngine", "SatelliteKit"],
            path: "Sources/SkyCore",
            resources: [.copy("Resources")]
        ),
        .executableTarget(name: "Nightwatch", dependencies: ["SkyCore"], path: "Sources/Nightwatch", exclude: ["Info.plist"]),
        .testTarget(
            name: "SkyCoreTests",
            dependencies: ["SkyCore"],
            path: "Tests/SkyCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
```

- [ ] **Step 2: Vendor Astronomy Engine and create the other scaffold files**

```bash
mkdir -p Sources/CAstronomyEngine/include Sources/SkyCore/Resources Sources/Nightwatch Tests/SkyCoreTests/Fixtures scripts
curl -sSL -o Sources/CAstronomyEngine/include/astronomy.h https://raw.githubusercontent.com/cosinekitty/astronomy/master/source/c/astronomy.h
curl -sSL -o Sources/CAstronomyEngine/astronomy.c https://raw.githubusercontent.com/cosinekitty/astronomy/master/source/c/astronomy.c
head -5 Sources/CAstronomyEngine/include/astronomy.h   # must show "MIT License"
printf '.build/\n.DS_Store\n.swiftpm/\n*.xcodeproj\nNightwatch.app/\n' > .gitignore
```

`scripts/test.sh`:

```bash
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
ARGS=()
[ -d "$PLUGINS" ] && ARGS=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
exec swift test "${ARGS[@]}" "$@"
```

`chmod +x scripts/test.sh`.

`LICENSE`: the MIT licence text with `Copyright (c) 2026 rsutcliffe`.

`NOTICE`:

```
Nightwatch bundles or fetches data from these sources. Their terms apply to that data.

Astronomy Engine, Don Cross, MIT. https://github.com/cosinekitty/astronomy
SatelliteKit, Gavin Eadie, MIT. https://github.com/gavineadie/SatelliteKit
Weather data by Open-Meteo.com, CC BY 4.0. https://open-meteo.com
Seeing and transparency from 7Timer (Shanghai Astronomical Observatory), non-commercial use. http://www.7timer.info
OpenNGC, Mattia Verga, CC BY-SA 4.0. https://github.com/mattiaverga/OpenNGC
Constellation figures from d3-celestial, Olaf Frohn, BSD-3-Clause. https://github.com/ofrohn/d3-celestial
Thumbnails via hips2fits, a service provided by CDS, Strasbourg. DSS images copyright AAO, SERC, Caltech and AURA. https://alasky.cds.unistra.fr/hips-image-services/hips2fits
Comet elements from the IAU Minor Planet Center. https://minorplanetcenter.net
ISS orbital elements from CelesTrak. https://celestrak.org
Meteor shower dates compiled from the International Meteor Organization calendar. https://www.imo.net
```

`README.md` (first version):

```markdown
# Nightwatch

Silent macOS menu-bar app: tells you when tonight is clear enough for a long imaging session, and what to point at.

## Build and install (any Mac, macOS 14+, no Xcode needed)

    xcode-select --install        # Command Line Tools, once
    git clone https://github.com/rsutcliffe/nightwatch.git && cd nightwatch
    scripts/fetch-data.sh         # catalogue and constellation data, once
    scripts/build-app.sh          # builds, signs ad hoc, installs to /Applications, launches

## Tests

    scripts/test.sh
```

`Sources/SkyCore/Time.swift`:

```swift
import CAstronomyEngine
import Foundation

/// Unix seconds at the J2000 epoch, 2000-01-01T12:00:00Z.
let j2000Unix: TimeInterval = 946_728_000

extension astro_time_t {
    init(_ date: Date) {
        self = Astronomy_TimeFromDays((date.timeIntervalSince1970 - j2000Unix) / 86_400)
    }
    var date: Date { Date(timeIntervalSince1970: ut * 86_400 + j2000Unix) }
}
```

`Sources/Nightwatch/NightwatchApp.swift` placeholder:

```swift
import SwiftUI
import SkyCore

@main
struct NightwatchApp: App {
    var body: some Scene {
        MenuBarExtra("Nightwatch", systemImage: "star") {
            Text("Nightwatch").padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 3: Write the failing test**

`Tests/SkyCoreTests/TimeTests.swift`:

```swift
import Testing
import Foundation
import CAstronomyEngine
@testable import SkyCore

@Test func j2000RoundTrip() {
    let d = Date(timeIntervalSince1970: 946_728_000)
    let t = astro_time_t(d)
    #expect(abs(t.ut) < 1e-9)
    #expect(abs(t.date.timeIntervalSince(d)) < 0.001)
}

@Test func arbitraryDateRoundTrip() {
    let d = Date(timeIntervalSince1970: 1_790_000_000)
    #expect(abs(astro_time_t(d).date.timeIntervalSince(d)) < 0.001)
}
```

- [ ] **Step 4: Run tests, expect failure before Time.swift exists, then pass**

Run: `scripts/test.sh`
Expected first run (if Time.swift is written last): compile error `cannot find 'astro_time_t'`. After adding Time.swift: `Test run with 2 tests in 0 suites passed`.

- [ ] **Step 5: Verify the executable also builds**

Run: `swift build -c release 2>&1 | tail -1`
Expected: `Build complete!` and `ls .build/release` shows `Nightwatch` and `Nightwatch_SkyCore.bundle`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: scaffold SwiftPM package with vendored Astronomy Engine and test script"
```

---

### Task 2: Site and Ephemeris

**Files:**
- Create: `Sources/SkyCore/Site.swift`, `Sources/SkyCore/Ephemeris.swift`
- Test: `Tests/SkyCoreTests/EphemerisTests.swift`

**Interfaces:**
- Consumes: `astro_time_t(Date)` / `.date` from Task 1.
- Produces:
  - `public struct Site: Codable, Equatable, Sendable { name, latitude, longitude, elevationM, timeZoneID, bortle; var timeZone: TimeZone }`
  - `public struct Night: Equatable, Sendable { key: String, localDate: Date, sunset: Date, sunrise: Date, darkStart: Date?, darkEnd: Date? }`
  - `public enum Planet: String, CaseIterable, Codable, Sendable { mercury, venus, mars, jupiter, saturn, uranus, neptune }`
  - `public struct BodyPosition: Sendable { raHours, decDeg, altDeg, azDeg, magnitude: Double? }`
  - `public struct MoonState: Sendable { illumination: Double, position: BodyPosition, rise: Date?, set: Date? }`
  - `public enum EclipseKind: String, Codable, Sendable { penumbral, partial, annular, total }`
  - `public struct LunarEclipse: Sendable { peak: Date, kind: EclipseKind, obscuration: Double }`
  - `public struct SolarEclipse: Sendable { peak: Date, kind: EclipseKind, obscuration: Double, partialBegin: Date?, partialEnd: Date? }`
  - `public enum Ephemeris` with static functions listed in Step 3.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

let sheffield = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
let sydney = Site(name: "Sydney", latitude: -33.87, longitude: 151.21, elevationM: 20, timeZoneID: "Australia/Sydney", bortle: 7)

func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: c)!
}

func close(_ a: Date, _ b: Date, minutes: Double) -> Bool { abs(a.timeIntervalSince(b)) <= minutes * 60 }

// Oracles: USNO sunset 18:02 UTC; sunrise-sunset.org astronomical twilight end 20:01:49, begin 03:54:39 (24th), sunrise 05:51:54 (24th).
@Test func sheffieldNightOracle() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: sheffield)
    #expect(night.key == "2026-09-23")
    #expect(close(night.sunset, utc(2026, 9, 23, 18, 3), minutes: 3))
    #expect(close(try #require(night.darkStart), utc(2026, 9, 23, 20, 2), minutes: 3))
    #expect(close(try #require(night.darkEnd), utc(2026, 9, 24, 3, 55), minutes: 3))
    #expect(close(night.sunrise, utc(2026, 9, 24, 5, 52), minutes: 3))
}

// Oracle: sunrise-sunset.org Sydney 2026-09-23: sunset 07:53:02 UTC, astronomical twilight end 09:15:09 UTC.
@Test func sydneyNightOracleSouthernHemisphere() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 2, 0), site: sydney)
    #expect(night.key == "2026-09-23")
    #expect(close(night.sunset, utc(2026, 9, 23, 7, 53), minutes: 3))
    #expect(close(try #require(night.darkStart), utc(2026, 9, 23, 9, 15), minutes: 3))
}

@Test func polarSummerHasNoAstronomicalDarkness() throws {
    let tromso = Site(name: "Tromsø", latitude: 69.65, longitude: 18.96, elevationM: 10, timeZoneID: "Europe/Oslo", bortle: 4)
    let night = try Ephemeris.night(localDate: utc(2026, 7, 20, 10, 0), site: tromso)
    #expect(night.darkStart == nil)
    #expect(night.darkEnd == nil)
}

@Test func polarisIsHighFromSheffield() {
    let p = Ephemeris.altAz(raHours: 2.53, decDeg: 89.26, at: utc(2026, 9, 23, 22, 0), site: sheffield)
    #expect(abs(p.alt - 53.4) < 1.5)
}

@Test func moonIlluminationInRange() {
    let m = Ephemeris.moon(at: utc(2026, 9, 23, 22, 0), site: sheffield)
    #expect(m.illumination >= 0 && m.illumination <= 1)
    #expect(m.position.altDeg > -90 && m.position.altDeg < 90)
}

@Test func separationOfIdenticalPointsIsZeroAndPolesIs180() {
    #expect(Ephemeris.separationDeg(ra1Hours: 1, dec1Deg: 10, ra2Hours: 1, dec2Deg: 10) < 1e-9)
    #expect(abs(Ephemeris.separationDeg(ra1Hours: 0, dec1Deg: 90, ra2Hours: 0, dec2Deg: -90) - 180) < 1e-9)
}

@Test func constellationLookup() {
    let c = Ephemeris.constellation(raHours: 5.6, decDeg: -5.4)   // M42
    #expect(c.symbol == "Ori")
}

@Test func nextLunarEclipseExists() {
    let e = Ephemeris.nextLunarEclipse(after: utc(2026, 9, 23, 0, 0))
    #expect(e != nil)
    #expect(e!.peak > utc(2026, 9, 23, 0, 0))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: compile errors `cannot find 'Site' in scope`, `cannot find 'Ephemeris' in scope`.

- [ ] **Step 3: Implement Site.swift and Ephemeris.swift**

`Sources/SkyCore/Site.swift`:

```swift
import CAstronomyEngine
import Foundation

public struct Site: Codable, Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var elevationM: Double
    public var timeZoneID: String
    public var bortle: Int

    public init(name: String, latitude: Double, longitude: Double, elevationM: Double, timeZoneID: String, bortle: Int) {
        self.name = name; self.latitude = latitude; self.longitude = longitude
        self.elevationM = elevationM; self.timeZoneID = timeZoneID; self.bortle = bortle
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    var observer: astro_observer_t { Astronomy_MakeObserver(latitude, longitude, elevationM) }
}
```

`Sources/SkyCore/Ephemeris.swift`:

```swift
import CAstronomyEngine
import Foundation

public struct Night: Equatable, Sendable {
    public let key: String
    public let localDate: Date
    public let sunset: Date
    public let sunrise: Date
    public let darkStart: Date?
    public let darkEnd: Date?
    public var hasDarkness: Bool { darkStart != nil && darkEnd != nil }
}

public enum Planet: String, CaseIterable, Codable, Sendable {
    case mercury, venus, mars, jupiter, saturn, uranus, neptune
    var body: astro_body_t {
        switch self {
        case .mercury: BODY_MERCURY
        case .venus: BODY_VENUS
        case .mars: BODY_MARS
        case .jupiter: BODY_JUPITER
        case .saturn: BODY_SATURN
        case .uranus: BODY_URANUS
        case .neptune: BODY_NEPTUNE
        }
    }
    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public struct BodyPosition: Sendable, Equatable {
    public let raHours: Double
    public let decDeg: Double
    public let altDeg: Double
    public let azDeg: Double
    public let magnitude: Double?
}

public struct MoonState: Sendable, Equatable {
    public let illumination: Double
    public let position: BodyPosition
    public let rise: Date?
    public let set: Date?
}

public enum EclipseKind: String, Codable, Sendable { case penumbral, partial, annular, total }
public struct LunarEclipse: Sendable, Equatable { public let peak: Date; public let kind: EclipseKind; public let obscuration: Double }
public struct SolarEclipse: Sendable, Equatable {
    public let peak: Date; public let kind: EclipseKind; public let obscuration: Double
    public let partialBegin: Date?; public let partialEnd: Date?
}

public enum EphemerisError: Error { case noSunEvent }

public enum Ephemeris {
    /// The night that begins on the local calendar date containing `localDate` at `site`.
    public static func night(localDate: Date, site: Site) throws -> Night {
        let cal = site.calendar
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: localDate)!
        let obs = site.observer
        let sunset = Astronomy_SearchRiseSetEx(BODY_SUN, obs, DIRECTION_SET, astro_time_t(noon), 1.0, 0)
        guard sunset.status == ASTRO_SUCCESS else { throw EphemerisError.noSunEvent }
        let sunrise = Astronomy_SearchRiseSetEx(BODY_SUN, obs, DIRECTION_RISE, sunset.time, 1.0, 0)
        guard sunrise.status == ASTRO_SUCCESS else { throw EphemerisError.noSunEvent }
        var darkStart: Date? = nil
        var darkEnd: Date? = nil
        let ds = Astronomy_SearchAltitude(BODY_SUN, obs, DIRECTION_SET, sunset.time, 1.0, -18)
        if ds.status == ASTRO_SUCCESS, ds.time.ut < sunrise.time.ut {
            let de = Astronomy_SearchAltitude(BODY_SUN, obs, DIRECTION_RISE, ds.time, 1.0, -18)
            if de.status == ASTRO_SUCCESS, de.time.ut <= sunrise.time.ut + 1e-6 {
                darkStart = ds.time.date
                darkEnd = de.time.date
            }
        }
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = site.timeZone; f.dateFormat = "yyyy-MM-dd"
        return Night(key: f.string(from: noon), localDate: noon, sunset: sunset.time.date, sunrise: sunrise.time.date,
                     darkStart: darkStart, darkEnd: darkEnd)
    }

    /// Altitude and azimuth of a J2000 RA/Dec. Catalogue coordinates are J2000; precession to date is ignored
    /// (ponytail: under 0.4 degrees in 2026, irrelevant for a 30 degree altitude floor).
    public static func altAz(raHours: Double, decDeg: Double, at date: Date, site: Site) -> (alt: Double, az: Double) {
        var t = astro_time_t(date)
        let h = Astronomy_Horizon(&t, site.observer, raHours, decDeg, REFRACTION_NORMAL)
        return (h.altitude, h.azimuth)
    }

    public static func position(of body: astro_body_t, at date: Date, site: Site) -> BodyPosition {
        var t = astro_time_t(date)
        let eq = Astronomy_Equator(body, &t, site.observer, EQUATOR_OF_DATE, ABERRATION)
        let h = Astronomy_Horizon(&t, site.observer, eq.ra, eq.dec, REFRACTION_NORMAL)
        let ill = Astronomy_Illumination(body, t)
        return BodyPosition(raHours: eq.ra, decDeg: eq.dec, altDeg: h.altitude, azDeg: h.azimuth,
                            magnitude: ill.status == ASTRO_SUCCESS ? ill.mag : nil)
    }

    public static func planet(_ p: Planet, at date: Date, site: Site) -> BodyPosition {
        position(of: p.body, at: date, site: site)
    }

    public static func moon(at date: Date, site: Site) -> MoonState {
        let t = astro_time_t(date)
        let ill = Astronomy_Illumination(BODY_MOON, t)
        let pos = position(of: BODY_MOON, at: date, site: site)
        let start = Astronomy_AddDays(t, -0.5)
        let rise = Astronomy_SearchRiseSetEx(BODY_MOON, site.observer, DIRECTION_RISE, start, 1.5, 0)
        let set = Astronomy_SearchRiseSetEx(BODY_MOON, site.observer, DIRECTION_SET, start, 1.5, 0)
        return MoonState(illumination: ill.phase_fraction, position: pos,
                         rise: rise.status == ASTRO_SUCCESS ? rise.time.date : nil,
                         set: set.status == ASTRO_SUCCESS ? set.time.date : nil)
    }

    public static func sunAltitude(at date: Date, site: Site) -> Double {
        position(of: BODY_SUN, at: date, site: site).altDeg
    }

    public static func separationDeg(ra1Hours: Double, dec1Deg: Double, ra2Hours: Double, dec2Deg: Double) -> Double {
        let d2r = Double.pi / 180
        let a1 = ra1Hours * 15 * d2r, a2 = ra2Hours * 15 * d2r
        let d1 = dec1Deg * d2r, d2 = dec2Deg * d2r
        let s = sin((d2 - d1) / 2), c = sin((a2 - a1) / 2)
        let h = s * s + cos(d1) * cos(d2) * c * c
        return 2 * asin(min(1, sqrt(h))) / d2r
    }

    public static func constellation(raHours: Double, decDeg: Double) -> (symbol: String, name: String) {
        let c = Astronomy_Constellation(raHours, decDeg)
        guard c.status == ASTRO_SUCCESS, let s = c.symbol, let n = c.name else { return ("", "") }
        return (String(cString: s), String(cString: n))
    }

    public static func nextLunarEclipse(after date: Date) -> LunarEclipse? {
        let e = Astronomy_SearchLunarEclipse(astro_time_t(date))
        guard e.status == ASTRO_SUCCESS, let kind = eclipseKind(e.kind) else { return nil }
        return LunarEclipse(peak: e.peak.date, kind: kind, obscuration: e.obscuration)
    }

    public static func nextLocalSolarEclipse(after date: Date, site: Site) -> SolarEclipse? {
        let e = Astronomy_SearchLocalSolarEclipse(astro_time_t(date), site.observer)
        guard e.status == ASTRO_SUCCESS, let kind = eclipseKind(e.kind) else { return nil }
        // Local eclipse events are astro_eclipse_event_t { time, altitude }, peak included.
        return SolarEclipse(peak: e.peak.time.date, kind: kind, obscuration: e.obscuration,
                            partialBegin: e.partial_begin.time.date, partialEnd: e.partial_end.time.date)
    }

    private static func eclipseKind(_ k: astro_eclipse_kind_t) -> EclipseKind? {
        switch k {
        case ECLIPSE_PENUMBRAL: .penumbral
        case ECLIPSE_PARTIAL: .partial
        case ECLIPSE_ANNULAR: .annular
        case ECLIPSE_TOTAL: .total
        default: nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all Ephemeris tests pass. If `sheffieldNightOracle` misses by more than 3 minutes, print the values and compare against the oracles in the test comments before changing tolerances; a sign error in longitude is the usual cause.

- [ ] **Step 5: Commit**

```bash
git add Sources/SkyCore/Site.swift Sources/SkyCore/Ephemeris.swift Tests/SkyCoreTests/EphemerisTests.swift
git commit -m "feat(skycore): site model and ephemeris wrapper with hemisphere oracles"
```

---
### Task 3: Forecast (Open-Meteo + 7Timer)

**Files:**
- Create: `Sources/SkyCore/Forecast.swift`
- Create: `Tests/SkyCoreTests/Fixtures/openmeteo.json`, `Tests/SkyCoreTests/Fixtures/seventimer.json`
- Test: `Tests/SkyCoreTests/ForecastTests.swift`

**Interfaces:**
- Consumes: `Site` (Task 2).
- Produces:
  - `public struct HourlyConditions: Codable, Equatable, Sendable { time: Date, cloudTotal: Int, cloudLow: Int?, cloudMid: Int?, cloudHigh: Int?, tempC: Double?, dewPointC: Double?, humidityPct: Int?, windKmh: Double?, gustKmh: Double?, visibilityM: Double?, seeing: Int?, transparency: Int? }`
  - `public struct Forecast: Codable, Equatable, Sendable { fetchedAt: Date, latitude: Double, longitude: Double, hours: [HourlyConditions], seeingSource: String? }`
  - `public protocol Fetcher: Sendable { func get(_ url: URL) async throws -> Data }`
  - `public enum OpenMeteo { static func url(latitude:longitude:days:) -> URL; static func parse(_ data: Data) throws -> [HourlyConditions] }`
  - `public struct SeeingSample: Equatable, Sendable { time: Date, seeing: Int, transparency: Int }`
  - `public enum SevenTimer { static func url(latitude:longitude:) -> URL; static func parse(_ data: Data) throws -> [SeeingSample] }`
  - `public enum ForecastService { static func merge(hours:seeing:) -> [HourlyConditions]; static func fetch(site:fetcher:now:) async throws -> Forecast }`

- [ ] **Step 1: Create fixtures from live responses**

```bash
curl -sS 'https://api.open-meteo.com/v1/forecast?latitude=53.38&longitude=-1.47&hourly=cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,dew_point_2m,temperature_2m,relative_humidity_2m,wind_speed_10m,wind_gusts_10m,visibility&timezone=auto&forecast_days=3' -o Tests/SkyCoreTests/Fixtures/openmeteo.json
curl -sS 'http://www.7timer.info/bin/api.pl?lon=-1.47&lat=53.38&product=astro&output=json' -o Tests/SkyCoreTests/Fixtures/seventimer.json
python3 -c "import json;d=json.load(open('Tests/SkyCoreTests/Fixtures/openmeteo.json'));print(len(d['hourly']['time']), d['utc_offset_seconds'])"
python3 -c "import json;d=json.load(open('Tests/SkyCoreTests/Fixtures/seventimer.json'));print(d['init'], len(d['dataseries']))"
```

Expected: `72 3600` (or the offset in force) and `<YYYYMMDDHH> 24`. Record both printed values; the tests below read them from the files, so no hard-coded dates.

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func openMeteoParsesSeventyTwoHoursInUTC() throws {
    let data = try fixture("openmeteo.json")
    let hours = try OpenMeteo.parse(data)
    #expect(hours.count == 72)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let offset = json["utc_offset_seconds"] as! Double
    let firstLocal = (json["hourly"] as! [String: Any])["time"] as! [String]
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; f.timeZone = TimeZone(identifier: "UTC")
    let expected = f.date(from: firstLocal[0])!.addingTimeInterval(-offset)
    #expect(hours[0].time == expected)
    #expect(hours[1].time.timeIntervalSince(hours[0].time) == 3600)
    #expect(hours[0].cloudTotal >= 0 && hours[0].cloudTotal <= 100)
    #expect(hours[0].visibilityM != nil)
    #expect(hours[0].seeing == nil)
}

@Test func openMeteoUrlHasRequiredVariables() {
    let u = OpenMeteo.url(latitude: 53.38, longitude: -1.47, days: 3).absoluteString
    #expect(u.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
    for v in ["cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high", "dew_point_2m", "temperature_2m", "relative_humidity_2m", "wind_speed_10m", "wind_gusts_10m", "visibility"] {
        #expect(u.contains(v))
    }
    #expect(u.contains("timezone=auto"))
    #expect(u.contains("forecast_days=3"))
}

@Test func sevenTimerParsesInitAndTimepoints() throws {
    let data = try fixture("seventimer.json")
    let samples = try SevenTimer.parse(data)
    #expect(samples.count == 24)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let initString = json["init"] as! String
    let f = DateFormatter(); f.dateFormat = "yyyyMMddHH"; f.timeZone = TimeZone(identifier: "UTC")
    let initDate = f.date(from: initString)!
    let firstTimepoint = ((json["dataseries"] as! [[String: Any]])[0]["timepoint"] as! Double)
    #expect(samples[0].time == initDate.addingTimeInterval(firstTimepoint * 3600))
    #expect((1...8).contains(samples[0].seeing))
    #expect((1...8).contains(samples[0].transparency))
}

@Test func mergeHoldsSeeingForThreeHoursOnly() {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    let hours = (0..<6).map { i in
        HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: 10, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                         tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
    }
    let seeing = [SeeingSample(time: t0, seeing: 3, transparency: 2)]
    let merged = ForecastService.merge(hours: hours, seeing: seeing)
    #expect(merged[0].seeing == 3)
    #expect(merged[2].seeing == 3)
    #expect(merged[3].seeing == nil)
    #expect(merged[2].transparency == 2)
}

struct StubFetcher: Fetcher {
    let byHost: [String: Data]
    func get(_ url: URL) async throws -> Data {
        guard let d = byHost[url.host ?? ""] else { throw URLError(.badURL) }
        return d
    }
}

@Test func fetchSurvivesSevenTimerFailure() async throws {
    let om = try fixture("openmeteo.json")
    let f = StubFetcher(byHost: ["api.open-meteo.com": om])
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let fc = try await ForecastService.fetch(site: site, fetcher: f, now: Date())
    #expect(fc.hours.count == 72)
    #expect(fc.seeingSource == nil)
}

@Test func fetchMergesSevenTimerWhenPresent() async throws {
    let f = StubFetcher(byHost: ["api.open-meteo.com": try fixture("openmeteo.json"), "www.7timer.info": try fixture("seventimer.json")])
    let site = Site(name: "S", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
    let fc = try await ForecastService.fetch(site: site, fetcher: f, now: Date())
    #expect(fc.seeingSource == "7Timer")
    #expect(fc.hours.contains { $0.seeing != nil })
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: compile errors `cannot find 'OpenMeteo' in scope`.

- [ ] **Step 4: Implement Forecast.swift**

```swift
import Foundation

public struct HourlyConditions: Codable, Equatable, Sendable {
    public var time: Date
    public var cloudTotal: Int
    public var cloudLow: Int?
    public var cloudMid: Int?
    public var cloudHigh: Int?
    public var tempC: Double?
    public var dewPointC: Double?
    public var humidityPct: Int?
    public var windKmh: Double?
    public var gustKmh: Double?
    public var visibilityM: Double?
    public var seeing: Int?
    public var transparency: Int?

    public init(time: Date, cloudTotal: Int, cloudLow: Int?, cloudMid: Int?, cloudHigh: Int?, tempC: Double?, dewPointC: Double?,
                humidityPct: Int?, windKmh: Double?, gustKmh: Double?, visibilityM: Double?, seeing: Int?, transparency: Int?) {
        self.time = time; self.cloudTotal = cloudTotal; self.cloudLow = cloudLow; self.cloudMid = cloudMid; self.cloudHigh = cloudHigh
        self.tempC = tempC; self.dewPointC = dewPointC; self.humidityPct = humidityPct; self.windKmh = windKmh; self.gustKmh = gustKmh
        self.visibilityM = visibilityM; self.seeing = seeing; self.transparency = transparency
    }
}

public struct Forecast: Codable, Equatable, Sendable {
    public var fetchedAt: Date
    public var latitude: Double
    public var longitude: Double
    public var hours: [HourlyConditions]
    public var seeingSource: String?
    public init(fetchedAt: Date, latitude: Double, longitude: Double, hours: [HourlyConditions], seeingSource: String?) {
        self.fetchedAt = fetchedAt; self.latitude = latitude; self.longitude = longitude; self.hours = hours; self.seeingSource = seeingSource
    }
}

public protocol Fetcher: Sendable {
    func get(_ url: URL) async throws -> Data
}

public struct URLSessionFetcher: Fetcher {
    public init() {}
    public func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Nightwatch/0.1 (https://github.com/rsutcliffe/nightwatch)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

public enum ForecastError: Error { case malformed(String) }

public enum OpenMeteo {
    static let variables = ["cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high", "dew_point_2m", "temperature_2m",
                            "relative_humidity_2m", "wind_speed_10m", "wind_gusts_10m", "visibility"]

    public static func url(latitude: Double, longitude: Double, days: Int) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "hourly", value: variables.joined(separator: ",")),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: String(days))
        ]
        return c.url!
    }

    private struct Payload: Decodable {
        let utc_offset_seconds: Double
        let hourly: Hourly
        struct Hourly: Decodable {
            let time: [String]
            let cloud_cover: [Int?]
            let cloud_cover_low: [Int?]?
            let cloud_cover_mid: [Int?]?
            let cloud_cover_high: [Int?]?
            let dew_point_2m: [Double?]?
            let temperature_2m: [Double?]?
            let relative_humidity_2m: [Int?]?
            let wind_speed_10m: [Double?]?
            let wind_gusts_10m: [Double?]?
            let visibility: [Double?]?
        }
    }

    public static func parse(_ data: Data) throws -> [HourlyConditions] {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        var out: [HourlyConditions] = []
        for (i, ts) in p.hourly.time.enumerated() {
            guard let local = f.date(from: ts) else { throw ForecastError.malformed("time \(ts)") }
            func at<T>(_ a: [T?]?) -> T? { guard let a, i < a.count else { return nil }; return a[i] }
            out.append(HourlyConditions(
                time: local.addingTimeInterval(-p.utc_offset_seconds),
                cloudTotal: at(p.hourly.cloud_cover) ?? 100,
                cloudLow: at(p.hourly.cloud_cover_low), cloudMid: at(p.hourly.cloud_cover_mid), cloudHigh: at(p.hourly.cloud_cover_high),
                tempC: at(p.hourly.temperature_2m), dewPointC: at(p.hourly.dew_point_2m), humidityPct: at(p.hourly.relative_humidity_2m),
                windKmh: at(p.hourly.wind_speed_10m), gustKmh: at(p.hourly.wind_gusts_10m), visibilityM: at(p.hourly.visibility),
                seeing: nil, transparency: nil))
        }
        return out
    }
}

public struct SeeingSample: Equatable, Sendable {
    public let time: Date
    public let seeing: Int
    public let transparency: Int
    public init(time: Date, seeing: Int, transparency: Int) { self.time = time; self.seeing = seeing; self.transparency = transparency }
}

public enum SevenTimer {
    public static func url(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: "http://www.7timer.info/bin/api.pl")!
        c.queryItems = [
            .init(name: "lon", value: String(format: "%.2f", longitude)),
            .init(name: "lat", value: String(format: "%.2f", latitude)),
            .init(name: "product", value: "astro"),
            .init(name: "output", value: "json")
        ]
        return c.url!
    }

    private struct Payload: Decodable {
        let `init`: String
        let dataseries: [Entry]
        struct Entry: Decodable { let timepoint: Double; let seeing: Int; let transparency: Int }
    }

    /// `init` is the model run in UTC as YYYYMMDDHH; `timepoint` is hours after that run (observed from live data, 2026-09-23).
    public static func parse(_ data: Data) throws -> [SeeingSample] {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHH"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let start = f.date(from: p.`init`) else { throw ForecastError.malformed("init \(p.`init`)") }
        return p.dataseries.map { SeeingSample(time: start.addingTimeInterval($0.timepoint * 3600), seeing: $0.seeing, transparency: $0.transparency) }
    }
}

public enum ForecastService {
    /// Attach the most recent 7Timer sample at or before each hour, held for at most 3 hours.
    public static func merge(hours: [HourlyConditions], seeing: [SeeingSample]) -> [HourlyConditions] {
        let sorted = seeing.sorted { $0.time < $1.time }
        return hours.map { h in
            var h = h
            if let s = sorted.last(where: { $0.time <= h.time }), h.time.timeIntervalSince(s.time) < 3 * 3600 {
                h.seeing = s.seeing
                h.transparency = s.transparency
            }
            return h
        }
    }

    public static func fetch(site: Site, fetcher: Fetcher, now: Date) async throws -> Forecast {
        let hours = try OpenMeteo.parse(try await fetcher.get(OpenMeteo.url(latitude: site.latitude, longitude: site.longitude, days: 3)))
        var seeingSource: String? = nil
        var merged = hours
        if let data = try? await fetcher.get(SevenTimer.url(latitude: site.latitude, longitude: site.longitude)),
           let samples = try? SevenTimer.parse(data), !samples.isEmpty {
            merged = merge(hours: hours, seeing: samples)
            seeingSource = "7Timer"
        }
        return Forecast(fetchedAt: now, latitude: site.latitude, longitude: site.longitude, hours: merged, seeingSource: seeingSource)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all Forecast tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SkyCore/Forecast.swift Tests/SkyCoreTests/ForecastTests.swift Tests/SkyCoreTests/Fixtures/openmeteo.json Tests/SkyCoreTests/Fixtures/seventimer.json
git commit -m "feat(skycore): Open-Meteo and 7Timer forecast parsing and merge"
```

---

### Task 4: Catalogue (OpenNGC) and constellations

**Files:**
- Create: `scripts/fetch-data.sh`, `Sources/SkyCore/Catalog.swift`
- Create (by script): `Sources/SkyCore/Resources/catalog/NGC.csv`, `addendum.csv`, `constellations.json`, `constellations.lines.json`
- Create: `Tests/SkyCoreTests/Fixtures/ngc-sample.csv`
- Test: `Tests/SkyCoreTests/CatalogTests.swift`

**Interfaces:**
- Produces:
  - `public enum TargetGroup: String, Codable, CaseIterable, Sendable { nebulae, galaxies, clusters, planets, events, constellations; displayName }`
  - `public struct DeepSkyObject: Codable, Equatable, Sendable, Identifiable { id: String, commonName: String?, messier: Int?, typeCode: String, group: TargetGroup, raHours: Double, decDeg: Double, majAxisArcmin: Double?, minAxisArcmin: Double?, magnitude: Double?, constellation: String; displayName }`
  - `public struct Catalog: Sendable { objects: [DeepSkyObject]; static func parse(csv: String) throws -> [DeepSkyObject]; static func bundled() throws -> Catalog }`
  - `public struct Constellation: Codable, Equatable, Sendable, Identifiable { id: String (3-letter), name: String, raHours: Double, decDeg: Double, lines: [[(raHours, decDeg)]] as [[[Double]]] }`
  - `public enum Constellations { static func bundled() throws -> [Constellation] }`
  - `public enum CatalogError: Error`

- [ ] **Step 1: Write fetch-data.sh and run it**

```bash
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
```

Run: `chmod +x scripts/fetch-data.sh && scripts/fetch-data.sh`
Expected: header begins `Name;Type;RA;Dec;Const;MajAx;MinAx;PosAng;B-Mag;V-Mag`; NGC.csv has more than 13,000 lines.

Create `Tests/SkyCoreTests/Fixtures/ngc-sample.csv` with the header line plus the rows for `NGC7000`, `NGC0224`, `NGC6720`, `NGC0869`, `IC0001`, `NGC7654` copied verbatim from NGC.csv (`grep -E '^(NGC7000|NGC0224|NGC6720|NGC0869|IC0001|NGC7654);' Sources/SkyCore/Resources/catalog/NGC.csv`), and the `Mel022` row from addendum.csv.

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

@Test func parsesSampleRows() throws {
    let csv = String(decoding: try fixture("ngc-sample.csv"), as: UTF8.self)
    let objs = try Catalog.parse(csv: csv)
    let m31 = try #require(objs.first { $0.id == "NGC0224" })
    #expect(m31.messier == 31)
    #expect(m31.group == .galaxies)
    #expect(abs(m31.raHours - 0.712) < 0.01)
    #expect(abs(m31.decDeg - 41.27) < 0.05)
    #expect((m31.majAxisArcmin ?? 0) > 100)
    #expect(m31.displayName.hasPrefix("M31"))
    let nan = try #require(objs.first { $0.id == "NGC7000" })
    #expect(nan.group == .nebulae)
    #expect(nan.commonName?.contains("North America") == true)
    let ring = try #require(objs.first { $0.id == "NGC6720" })
    #expect(ring.group == .nebulae && ring.messier == 57)
    let dbl = try #require(objs.first { $0.id == "NGC0869" })
    #expect(dbl.group == .clusters)
    #expect(objs.first { $0.id == "IC0001" } == nil)   // double star, no group
    let pleiades = try #require(objs.first { $0.id == "Mel022" })
    #expect(pleiades.messier == 45 && pleiades.group == .clusters)
}

@Test func bundledCatalogLoads() throws {
    let cat = try Catalog.bundled()
    #expect(cat.objects.count > 5000)
    #expect(cat.objects.filter { $0.messier != nil }.count >= 100)
}

@Test func bundledConstellationsLoad() throws {
    let cs = try Constellations.bundled()
    #expect(cs.count == 88 || cs.count == 89)
    let ori = try #require(cs.first { $0.id == "Ori" })
    #expect(ori.name == "Orion")
    #expect(!ori.lines.isEmpty)
    #expect(ori.raHours >= 0 && ori.raHours < 24)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'Catalog' in scope`.

- [ ] **Step 4: Implement Catalog.swift**

```swift
import Foundation

public enum TargetGroup: String, Codable, CaseIterable, Sendable {
    case nebulae, galaxies, clusters, planets, events, constellations
    public var displayName: String {
        switch self {
        case .nebulae: "Nebulae"
        case .galaxies: "Galaxies"
        case .clusters: "Star clusters"
        case .planets: "Planets and Moon"
        case .events: "Events"
        case .constellations: "Constellations"
        }
    }
}

public struct DeepSkyObject: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let commonName: String?
    public let messier: Int?
    public let typeCode: String
    public let group: TargetGroup
    public let raHours: Double
    public let decDeg: Double
    public let majAxisArcmin: Double?
    public let minAxisArcmin: Double?
    public let magnitude: Double?
    public let constellation: String

    public var displayName: String {
        var parts: [String] = []
        if let m = messier { parts.append("M\(m)") }
        parts.append(id.replacingOccurrences(of: "NGC0", with: "NGC ").replacingOccurrences(of: "IC0", with: "IC ")
            .replacingOccurrences(of: "NGC", with: "NGC ").replacingOccurrences(of: "  ", with: " "))
        if let c = commonName { parts.append(c) }
        return parts.joined(separator: " · ")
    }
}

public enum CatalogError: Error { case missingResource(String), badHeader }

public struct Catalog: Sendable {
    public let objects: [DeepSkyObject]

    static let groupByType: [String: TargetGroup] = [
        "G": .galaxies, "GPair": .galaxies, "GTrpl": .galaxies, "GGroup": .galaxies,
        "OCl": .clusters, "GCl": .clusters, "Cl+N": .clusters, "*Ass": .clusters,
        "PN": .nebulae, "HII": .nebulae, "EmN": .nebulae, "Neb": .nebulae, "RfN": .nebulae, "SNR": .nebulae, "DrkN": .nebulae
    ]

    static func hours(_ s: String) -> Double? {
        let p = s.split(separator: ":").compactMap { Double($0) }
        guard p.count == 3 else { return nil }
        return p[0] + p[1] / 60 + p[2] / 3600
    }

    static func degrees(_ s: String) -> Double? {
        guard let first = s.first else { return nil }
        let sign: Double = first == "-" ? -1 : 1
        let body = (first == "-" || first == "+") ? String(s.dropFirst()) : s
        let p = body.split(separator: ":").compactMap { Double($0) }
        guard p.count == 3 else { return nil }
        return sign * (p[0] + p[1] / 60 + p[2] / 3600)
    }

    public static func parse(csv: String) throws -> [DeepSkyObject] {
        var lines = csv.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst().split(separator: ";").map(String.init)
        guard header.count > 28 else { throw CatalogError.badHeader }
        let col = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        func field(_ row: [String], _ name: String) -> String {
            guard let i = col[name], i < row.count else { return "" }
            return row[i]
        }
        var out: [DeepSkyObject] = []
        for line in lines {
            let row = line.components(separatedBy: ";")
            let type = field(row, "Type")
            guard let group = groupByType[type],
                  let ra = hours(field(row, "RA")), let dec = degrees(field(row, "Dec")) else { continue }
            let v = Double(field(row, "V-Mag")), b = Double(field(row, "B-Mag"))
            let names = field(row, "Common names")
            out.append(DeepSkyObject(
                id: field(row, "Name"),
                commonName: names.isEmpty ? nil : names.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) },
                messier: Int(field(row, "M")),
                typeCode: type, group: group, raHours: ra, decDeg: dec,
                majAxisArcmin: Double(field(row, "MajAx")), minAxisArcmin: Double(field(row, "MinAx")),
                magnitude: v ?? b, constellation: field(row, "Const")))
        }
        return out
    }

    public static func bundled() throws -> Catalog {
        var all: [DeepSkyObject] = []
        for name in ["NGC", "addendum"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Resources/catalog") else {
                throw CatalogError.missingResource(name)
            }
            all += try parse(csv: String(contentsOf: url, encoding: .utf8))
        }
        return Catalog(objects: all)
    }
}

public struct Constellation: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let raHours: Double
    public let decDeg: Double
    /// Stick-figure polylines, each point [raHours, decDeg].
    public let lines: [[[Double]]]
}

public enum Constellations {
    private struct Collection: Decodable { let features: [Feature] }
    private struct Feature: Decodable {
        let id: String
        let properties: [String: AnyCodableValue]?
        let geometry: Geometry
        struct Geometry: Decodable { let type: String; let coordinates: AnyCodableValue }
    }

    /// d3-celestial stores RA in degrees from -180 to 180; convert to hours 0..24.
    static func hours(fromDegrees d: Double) -> Double {
        var h = d / 15
        if h < 0 { h += 24 }
        return h
    }

    public static func bundled() throws -> [Constellation] {
        guard let cUrl = Bundle.module.url(forResource: "constellations", withExtension: "json", subdirectory: "Resources/catalog"),
              let lUrl = Bundle.module.url(forResource: "constellations.lines", withExtension: "json", subdirectory: "Resources/catalog") else {
            throw CatalogError.missingResource("constellations")
        }
        let centres = try JSONDecoder().decode(Collection.self, from: Data(contentsOf: cUrl))
        let figures = try JSONDecoder().decode(Collection.self, from: Data(contentsOf: lUrl))
        let linesByID: [String: [[[Double]]]] = Dictionary(uniqueKeysWithValues: figures.features.map { f in
            let raw = f.geometry.coordinates.doubleArrays3
            return (f.id, raw.map { line in line.map { [hours(fromDegrees: $0[0]), $0[1]] } })
        })
        return centres.features.compactMap { f in
            guard let pt = f.geometry.coordinates.doubleArray, pt.count == 2 else { return nil }
            let name = f.properties?["name"]?.string ?? f.id
            return Constellation(id: f.id, name: name, raHours: hours(fromDegrees: pt[0]), decDeg: pt[1], lines: linesByID[f.id] ?? [])
        }
    }
}

/// Minimal JSON value for the loosely typed GeoJSON files.
public enum AnyCodableValue: Decodable, Sendable {
    case string(String), number(Double), bool(Bool), array([AnyCodableValue]), object([String: AnyCodableValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([AnyCodableValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: AnyCodableValue].self)) }
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var double: Double? { if case .number(let n) = self { return n }; return nil }
    var doubleArray: [Double]? { if case .array(let a) = self { return a.compactMap(\.double) }; return nil }
    var doubleArrays3: [[[Double]]] {
        if case .array(let lines) = self {
            return lines.compactMap { line -> [[Double]]? in
                if case .array(let pts) = line { return pts.compactMap(\.doubleArray) }
                return nil
            }
        }
        return []
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all Catalog tests pass. If `bundledConstellationsLoad` finds no lines for Ori, print `figures.features.first?.geometry.type`; a `LineString` (single polyline) geometry needs wrapping as `[coordinates]` before `doubleArrays3`.

- [ ] **Step 6: Commit**

```bash
git add scripts/fetch-data.sh Sources/SkyCore/Catalog.swift Sources/SkyCore/Resources/catalog Tests/SkyCoreTests/CatalogTests.swift Tests/SkyCoreTests/Fixtures/ngc-sample.csv
git commit -m "feat(skycore): OpenNGC catalogue and d3-celestial constellation loading"
```

---
### Task 5: Planner — darkness windows and score

**Files:**
- Create: `Sources/SkyCore/Planner.swift` (windows and score only; ranking is Task 6)
- Test: `Tests/SkyCoreTests/PlannerWindowTests.swift`

**Interfaces:**
- Consumes: `Night`, `HourlyConditions`, `MoonState`, `Site`, `Ephemeris.moon`.
- Produces:
  - `public struct GoRule: Codable, Equatable, Sendable { minHours: Double = 3, maxCloudPct: Int = 25, minAltitudeDeg: Double = 30 }`
  - `public struct ClearWindow: Codable, Equatable, Sendable { start: Date, end: Date; var hours: Double }`
  - `public struct ScoreInputs { darkHours: [HourlyConditions], windows: [ClearWindow], darkness: (Date, Date)?, moonIllumination: Double, moonAboveFraction: Double }`
  - `Planner.windows(hours:darkStart:darkEnd:rule:) -> [ClearWindow]`
  - `Planner.score(_ inputs: ScoreInputs) -> Int`
  - `Planner.darkHours(_ hours: [HourlyConditions], night: Night) -> [HourlyConditions]`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

private func hour(_ t0: Date, _ i: Int, cloud: Int, wind: Double? = nil, temp: Double? = nil, dew: Double? = nil, seeing: Int? = nil, transp: Int? = nil) -> HourlyConditions {
    HourlyConditions(time: t0.addingTimeInterval(Double(i) * 3600), cloudTotal: cloud, cloudLow: nil, cloudMid: nil, cloudHigh: nil,
                     tempC: temp, dewPointC: dew, humidityPct: nil, windKmh: wind, gustKmh: nil, visibilityM: nil, seeing: seeing, transparency: transp)
}

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)   // any fixed instant
private let rule = GoRule()

@Test func oneClearWindowClippedToDarkness() {
    // darkness 20:30 -> 04:30 relative to t0 = 20:00
    let dark = (t0.addingTimeInterval(1800), t0.addingTimeInterval(8.5 * 3600))
    let hours = (0..<12).map { hour(t0, $0, cloud: $0 < 2 ? 80 : ($0 < 8 ? 10 : 90)) }   // clear 22:00–04:00
    let w = Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule)
    #expect(w.count == 1)
    #expect(w[0].start == t0.addingTimeInterval(2 * 3600))
    #expect(w[0].end == t0.addingTimeInterval(8 * 3600))
    #expect(w[0].hours == 6)
}

@Test func windowShorterThanRuleIsDropped() {
    let dark = (t0, t0.addingTimeInterval(10 * 3600))
    let hours = (0..<10).map { hour(t0, $0, cloud: (3...4).contains($0) ? 0 : 90) }   // 2 h clear
    #expect(Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule).isEmpty)
}

@Test func twoWindowsSortedLongestFirstByCaller() {
    let dark = (t0, t0.addingTimeInterval(12 * 3600))
    let hours = (0..<12).map { hour(t0, $0, cloud: ((0...2).contains($0) || (5...9).contains($0)) ? 5 : 95) }
    let w = Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule)
    #expect(w.count == 2)
    #expect(w.map(\.hours) == [3, 5])
}

@Test func windowCrossingMidnightIsContiguous() {
    // t0 = 22:00, darkness 22:00 -> 05:00; clear 23:00 -> 03:00 spans midnight
    let dark = (t0, t0.addingTimeInterval(7 * 3600))
    let hours = (0..<7).map { hour(t0, $0, cloud: (1...4).contains($0) ? 0 : 100) }
    let w = Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule)
    #expect(w.count == 1 && w[0].hours == 4)
}

@Test func cloudAtThresholdCounts() {
    let dark = (t0, t0.addingTimeInterval(4 * 3600))
    let hours = (0..<4).map { hour(t0, $0, cloud: 25) }
    #expect(Planner.windows(hours: hours, darkStart: dark.0, darkEnd: dark.1, rule: rule).count == 1)
}

@Test func scoreExtremes() {
    let dark = (t0, t0.addingTimeInterval(8 * 3600))
    let clear = (0..<8).map { hour(t0, $0, cloud: 0, wind: 5, temp: 10, dew: 2, seeing: 1, transp: 1) }
    let overcast = (0..<8).map { hour(t0, $0, cloud: 100, wind: 50, temp: 10, dew: 9.5) }
    let full = ScoreInputs(darkHours: clear, windows: [ClearWindow(start: dark.0, end: dark.1)], darkness: dark, moonIllumination: 0, moonAboveFraction: 0)
    let none = ScoreInputs(darkHours: overcast, windows: [], darkness: dark, moonIllumination: 1, moonAboveFraction: 1)
    #expect(Planner.score(full) == 100)
    #expect(Planner.score(none) == 0)
}

@Test func scoreWithoutSeeingRedistributesWeight() {
    let dark = (t0, t0.addingTimeInterval(8 * 3600))
    let clear = (0..<8).map { hour(t0, $0, cloud: 0, wind: 5, temp: 10, dew: 2) }
    let s = Planner.score(ScoreInputs(darkHours: clear, windows: [ClearWindow(start: dark.0, end: dark.1)], darkness: dark, moonIllumination: 0, moonAboveFraction: 0))
    #expect(s == 100)
}

@Test func fullMoonAllNightCostsFifteen() {
    let dark = (t0, t0.addingTimeInterval(8 * 3600))
    let clear = (0..<8).map { hour(t0, $0, cloud: 0, wind: 5, temp: 10, dew: 2, seeing: 1, transp: 1) }
    let s = Planner.score(ScoreInputs(darkHours: clear, windows: [ClearWindow(start: dark.0, end: dark.1)], darkness: dark, moonIllumination: 1, moonAboveFraction: 1))
    #expect(s == 85)
}

@Test func noDarknessScoresZero() {
    #expect(Planner.score(ScoreInputs(darkHours: [], windows: [], darkness: nil, moonIllumination: 0, moonAboveFraction: 0)) == 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'Planner' in scope`.

- [ ] **Step 3: Implement the first half of Planner.swift**

```swift
import Foundation

public struct GoRule: Codable, Equatable, Sendable {
    public var minHours: Double
    public var maxCloudPct: Int
    public var minAltitudeDeg: Double
    public init(minHours: Double = 3, maxCloudPct: Int = 25, minAltitudeDeg: Double = 30) {
        self.minHours = minHours; self.maxCloudPct = maxCloudPct; self.minAltitudeDeg = minAltitudeDeg
    }
}

public struct ClearWindow: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
    public var hours: Double { end.timeIntervalSince(start) / 3600 }
    public var midpoint: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
}

public struct ScoreInputs {
    public var darkHours: [HourlyConditions]
    public var windows: [ClearWindow]
    public var darkness: (Date, Date)?
    public var moonIllumination: Double
    public var moonAboveFraction: Double
    public init(darkHours: [HourlyConditions], windows: [ClearWindow], darkness: (Date, Date)?, moonIllumination: Double, moonAboveFraction: Double) {
        self.darkHours = darkHours; self.windows = windows; self.darkness = darkness
        self.moonIllumination = moonIllumination; self.moonAboveFraction = moonAboveFraction
    }
}

public enum Planner {
    /// Hourly samples that overlap the night's darkness. A sample at time t covers [t, t + 1 h).
    public static func darkHours(_ hours: [HourlyConditions], night: Night) -> [HourlyConditions] {
        guard let ds = night.darkStart, let de = night.darkEnd else { return [] }
        return hours.filter { $0.time.addingTimeInterval(3600) > ds && $0.time < de }.sorted { $0.time < $1.time }
    }

    /// Maximal runs of consecutive hourly samples inside darkness with cloud at or under the rule, at least `minHours` long.
    public static func windows(hours: [HourlyConditions], darkStart: Date, darkEnd: Date, rule: GoRule) -> [ClearWindow] {
        let dark = hours.filter { $0.time.addingTimeInterval(3600) > darkStart && $0.time < darkEnd }.sorted { $0.time < $1.time }
        var out: [ClearWindow] = []
        var run: [HourlyConditions] = []
        func flush() {
            guard let f = run.first, let l = run.last else { return }
            let w = ClearWindow(start: max(f.time, darkStart), end: min(l.time.addingTimeInterval(3600), darkEnd))
            if w.hours >= rule.minHours { out.append(w) }
            run = []
        }
        for h in dark {
            let clear = h.cloudTotal <= rule.maxCloudPct
            let contiguous = run.last.map { h.time.timeIntervalSince($0.time) == 3600 } ?? true
            if clear && contiguous { run.append(h) } else { flush(); if clear { run = [h] } }
        }
        flush()
        return out
    }

    /// 0–100. Cloud 60 (75 without seeing data), Moon 15, seeing + transparency 15, wind and dew 10.
    public static func score(_ s: ScoreInputs) -> Int {
        guard let (ds, de) = s.darkness, de > ds, !s.darkHours.isEmpty else { return 0 }
        let clearHours = Double(s.darkHours.filter { $0.cloudTotal <= 25 }.count)
        let totalHours = Double(s.darkHours.count)
        let clearFraction = min(1, clearHours / totalHours)
        let primaryHours = s.windows.map(\.hours).max() ?? 0
        let contiguity = clearHours > 0 ? min(1, primaryHours / clearHours) : 0
        let seeingSamples = s.darkHours.compactMap(\.seeing)
        let transSamples = s.darkHours.compactMap(\.transparency)
        let hasSeeing = !seeingSamples.isEmpty && !transSamples.isEmpty
        let cloudWeight = hasSeeing ? 60.0 : 75.0
        let cloudScore = cloudWeight * clearFraction * (0.5 + 0.5 * contiguity)
        let moonScore = 15 * (1 - s.moonIllumination * s.moonAboveFraction)
        var seeingScore = 0.0
        if hasSeeing {
            let avgS = Double(seeingSamples.reduce(0, +)) / Double(seeingSamples.count)
            let avgT = Double(transSamples.reduce(0, +)) / Double(transSamples.count)
            seeingScore = 7.5 * (1 - (avgS - 1) / 7) + 7.5 * (1 - (avgT - 1) / 7)
        }
        let winds = s.darkHours.compactMap(\.windKmh)
        let avgWind = winds.isEmpty ? 0 : winds.reduce(0, +) / Double(winds.count)
        let windPenalty = min(1, max(0, (avgWind - 10) / 30)) * 5      // no penalty under 10 km/h, full at 40
        let spreads = s.darkHours.compactMap { h -> Double? in
            guard let t = h.tempC, let d = h.dewPointC else { return nil }
            return t - d
        }
        let minSpread = spreads.min() ?? 10
        let dewPenalty: Double = minSpread < 2 ? 5 : (minSpread < 4 ? 2.5 : 0)
        let total = cloudScore + moonScore + seeingScore + (10 - windPenalty - dewPenalty)
        return max(0, min(100, Int(total.rounded())))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all PlannerWindow tests pass. `scoreExtremes` overcast case: cloud 0, Moon 15·(1−1)=0, seeing absent so cloud weight is 75 but fraction 0, wind 50 km/h → penalty 5, spread 0.5 → penalty 5, total 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/SkyCore/Planner.swift Tests/SkyCoreTests/PlannerWindowTests.swift
git commit -m "feat(skycore): clear-window finder and sky score"
```

---

### Task 6: Planner — target ranking and the NightPlan

**Files:**
- Modify: `Sources/SkyCore/Planner.swift` (append)
- Test: `Tests/SkyCoreTests/PlannerRankTests.swift`

**Interfaces:**
- Consumes: `Catalog`, `Constellation`, `Ephemeris.altAz/moon/planet`, `ClearWindow`, `GoRule`.
- Produces:
  - `public struct FieldOfView: Codable, Equatable, Sendable { widthDeg: Double, heightDeg: Double }`
  - `public enum FrameFit: String, Codable, Sendable { fits, small, mosaic }`
  - `public struct RankedTarget: Codable, Equatable, Sendable, Identifiable { id, name, subtitle, group: TargetGroup, raHours, decDeg, sizeArcmin: Double?, magnitude: Double?, fit: FrameFit, peakAltDeg: Double, peakTime: Date, moonSepDeg: Double, moonWashed: Bool, visibleFraction: Double }`
  - `public struct NightPlan: Codable, Equatable, Sendable { night: Night, windows: [ClearWindow], primary: ClearWindow?, score: Int, qualifies: Bool, moonIllumination: Double, moonRise: Date?, moonSet: Date?, darkHours: [HourlyConditions], targets: [RankedTarget], best: [RankedTarget], seeingAvailable: Bool }`
  - `Planner.frameFit(sizeArcmin:fov:) -> FrameFit`
  - `Planner.rank(catalog:constellations:window:site:fov:rule:) -> [RankedTarget]`
  - `Planner.plan(night:forecast:catalog:constellations:site:fov:rule:) -> NightPlan`
- `Night` must gain `Codable` (add the conformance in Ephemeris.swift; it is a plain struct of Dates and Strings).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

private let sheffieldSite = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private let dwarfMini = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)

@Test func frameFitThresholds() {
    #expect(Planner.frameFit(sizeArcmin: 3, fov: dwarfMini) == .small)
    #expect(Planner.frameFit(sizeArcmin: 60, fov: dwarfMini) == .fits)
    #expect(Planner.frameFit(sizeArcmin: 178, fov: dwarfMini) == .mosaic)   // M31 at 2.97 degrees
    #expect(Planner.frameFit(sizeArcmin: 500, fov: dwarfMini) == .mosaic)
    #expect(Planner.frameFit(sizeArcmin: nil, fov: dwarfMini) == .small)
}

@Test func ranksNorthAmericaNebulaOnASeptemberNight() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: sheffieldSite)
    let window = ClearWindow(start: night.darkStart!, end: night.darkStart!.addingTimeInterval(4 * 3600))
    let cat = try Catalog.bundled()
    let cons = try Constellations.bundled()
    let ranked = Planner.rank(catalog: cat, constellations: cons, window: window, site: sheffieldSite, fov: dwarfMini, rule: GoRule())
    let nan = try #require(ranked.first { $0.id == "NGC7000" })
    #expect(nan.group == .nebulae)
    #expect(nan.peakAltDeg > 60)
    #expect(nan.fit == .fits)
    #expect(ranked.contains { $0.group == .planets })
    #expect(ranked.contains { $0.group == .constellations && $0.id == "Cyg" })
    #expect(!ranked.contains { $0.id == "NGC1976" })   // Orion is below 30 degrees in that window
    let nebulae = ranked.filter { $0.group == .nebulae }
    #expect(nebulae.count > 3)
    #expect(nebulae.allSatisfy { $0.visibleFraction >= 0.5 })
}

@Test func planQualifiesWhenForecastIsClear() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: sheffieldSite)
    let start = night.sunset.addingTimeInterval(-3600)
    let hours = (0..<14).map { i in
        HourlyConditions(time: start.addingTimeInterval(Double(i) * 3600), cloudTotal: 5, cloudLow: 0, cloudMid: 0, cloudHigh: 5,
                         tempC: 10, dewPointC: 3, humidityPct: 60, windKmh: 8, gustKmh: 15, visibilityM: 20000, seeing: 3, transparency: 3)
    }
    let fc = Forecast(fetchedAt: start, latitude: 53.38, longitude: -1.47, hours: hours, seeingSource: "7Timer")
    let plan = Planner.plan(night: night, forecast: fc, catalog: try Catalog.bundled(), constellations: try Constellations.bundled(),
                            site: sheffieldSite, fov: dwarfMini, rule: GoRule())
    #expect(plan.qualifies)
    #expect(plan.primary != nil)
    #expect(plan.score >= 70)
    #expect(plan.best.count == 3)
    #expect(Set(plan.best.map(\.group)).count == 3)
    #expect(plan.seeingAvailable)
}

@Test func planDoesNotQualifyWhenOvercast() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: sheffieldSite)
    let start = night.sunset.addingTimeInterval(-3600)
    let hours = (0..<14).map { i in
        HourlyConditions(time: start.addingTimeInterval(Double(i) * 3600), cloudTotal: 90, cloudLow: 90, cloudMid: nil, cloudHigh: nil,
                         tempC: nil, dewPointC: nil, humidityPct: nil, windKmh: nil, gustKmh: nil, visibilityM: nil, seeing: nil, transparency: nil)
    }
    let fc = Forecast(fetchedAt: start, latitude: 53.38, longitude: -1.47, hours: hours, seeingSource: nil)
    let plan = Planner.plan(night: night, forecast: fc, catalog: Catalog(objects: []), constellations: [], site: sheffieldSite, fov: dwarfMini, rule: GoRule())
    #expect(!plan.qualifies)
    #expect(plan.primary == nil)
    #expect(plan.targets.isEmpty)
    #expect(plan.score < 30)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'FieldOfView' in scope`.

- [ ] **Step 3: Append the ranking half to Planner.swift**

```swift
public struct FieldOfView: Codable, Equatable, Sendable {
    public var widthDeg: Double
    public var heightDeg: Double
    public init(widthDeg: Double, heightDeg: Double) { self.widthDeg = widthDeg; self.heightDeg = heightDeg }
}

public enum FrameFit: String, Codable, Sendable { case fits, small, mosaic }

public struct RankedTarget: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let group: TargetGroup
    public let raHours: Double
    public let decDeg: Double
    public let sizeArcmin: Double?
    public let magnitude: Double?
    public let fit: FrameFit
    public let peakAltDeg: Double
    public let peakTime: Date
    public let moonSepDeg: Double
    public let moonWashed: Bool
    public let visibleFraction: Double
}

public struct NightPlan: Codable, Equatable, Sendable {
    public let night: Night
    public let windows: [ClearWindow]
    public let primary: ClearWindow?
    public let score: Int
    public let qualifies: Bool
    public let moonIllumination: Double
    public let moonRise: Date?
    public let moonSet: Date?
    public let darkHours: [HourlyConditions]
    public let targets: [RankedTarget]
    public let best: [RankedTarget]
    public let seeingAvailable: Bool
}

extension Planner {
    public static func frameFit(sizeArcmin: Double?, fov: FieldOfView) -> FrameFit {
        guard let s = sizeArcmin, s >= 5 else { return .small }
        let deg = s / 60
        if deg <= min(fov.widthDeg, fov.heightDeg) { return .fits }
        return .mosaic
    }

    /// Sample a window every 30 minutes; returns fraction of samples at or above `minAlt`, the peak altitude and its time.
    static func track(raHours: Double, decDeg: Double, window: ClearWindow, site: Site, minAlt: Double) -> (fraction: Double, peakAlt: Double, peakTime: Date) {
        var t = window.start
        var above = 0, n = 0
        var peak = -90.0, peakTime = window.start
        while t <= window.end {
            let alt = Ephemeris.altAz(raHours: raHours, decDeg: decDeg, at: t, site: site).alt
            n += 1
            if alt >= minAlt { above += 1 }
            if alt > peak { peak = alt; peakTime = t }
            t = t.addingTimeInterval(1800)
        }
        return (n == 0 ? 0 : Double(above) / Double(n), peak, peakTime)
    }

    public static func rank(catalog: Catalog, constellations: [Constellation], window: ClearWindow, site: Site, fov: FieldOfView, rule: GoRule) -> [RankedTarget] {
        let moon = Ephemeris.moon(at: window.midpoint, site: site)
        let moonUp = moon.position.altDeg > 0 && moon.illumination > 0.1
        var out: [RankedTarget] = []

        for o in catalog.objects {
            guard let mag = o.magnitude, mag <= 12 else { continue }
            let tr = track(raHours: o.raHours, decDeg: o.decDeg, window: window, site: site, minAlt: rule.minAltitudeDeg)
            guard tr.fraction >= 0.5 else { continue }
            let sep = Ephemeris.separationDeg(ra1Hours: o.raHours, dec1Deg: o.decDeg, ra2Hours: moon.position.raHours, dec2Deg: moon.position.decDeg)
            out.append(RankedTarget(id: o.id, name: o.displayName, subtitle: "\(o.typeCode) in \(o.constellation)", group: o.group,
                                    raHours: o.raHours, decDeg: o.decDeg, sizeArcmin: o.majAxisArcmin, magnitude: mag,
                                    fit: frameFit(sizeArcmin: o.majAxisArcmin, fov: fov), peakAltDeg: tr.peakAlt, peakTime: tr.peakTime,
                                    moonSepDeg: sep, moonWashed: moonUp && sep < 30, visibleFraction: tr.fraction))
        }

        for p in Planet.allCases {
            let pos = Ephemeris.planet(p, at: window.midpoint, site: site)
            let tr = track(raHours: pos.raHours, decDeg: pos.decDeg, window: window, site: site, minAlt: rule.minAltitudeDeg)
            guard tr.fraction >= 0.5 else { continue }
            let sep = Ephemeris.separationDeg(ra1Hours: pos.raHours, dec1Deg: pos.decDeg, ra2Hours: moon.position.raHours, dec2Deg: moon.position.decDeg)
            out.append(RankedTarget(id: "planet-\(p.rawValue)", name: p.displayName, subtitle: "Planet", group: .planets,
                                    raHours: pos.raHours, decDeg: pos.decDeg, sizeArcmin: nil, magnitude: pos.magnitude, fit: .small,
                                    peakAltDeg: tr.peakAlt, peakTime: tr.peakTime, moonSepDeg: sep, moonWashed: false, visibleFraction: tr.fraction))
        }
        if moon.illumination > 0.05 {
            let tr = track(raHours: moon.position.raHours, decDeg: moon.position.decDeg, window: window, site: site, minAlt: 10)
            if tr.fraction > 0 {
                out.append(RankedTarget(id: "moon", name: "Moon", subtitle: "\(Int((moon.illumination * 100).rounded()))% illuminated", group: .planets,
                                        raHours: moon.position.raHours, decDeg: moon.position.decDeg, sizeArcmin: 31, magnitude: nil,
                                        fit: frameFit(sizeArcmin: 31, fov: fov), peakAltDeg: tr.peakAlt, peakTime: tr.peakTime,
                                        moonSepDeg: 0, moonWashed: false, visibleFraction: tr.fraction))
            }
        }

        for c in constellations {
            let tr = track(raHours: c.raHours, decDeg: c.decDeg, window: window, site: site, minAlt: 20)
            guard tr.fraction >= 0.5 else { continue }
            out.append(RankedTarget(id: c.id, name: c.name, subtitle: "Constellation", group: .constellations,
                                    raHours: c.raHours, decDeg: c.decDeg, sizeArcmin: nil, magnitude: nil, fit: .mosaic,
                                    peakAltDeg: tr.peakAlt, peakTime: tr.peakTime, moonSepDeg: 0, moonWashed: false, visibleFraction: tr.fraction))
        }

        let fitOrder: [FrameFit: Int] = [.fits: 0, .small: 1, .mosaic: 2]
        return out.sorted {
            if $0.group != $1.group { return TargetGroup.allCases.firstIndex(of: $0.group)! < TargetGroup.allCases.firstIndex(of: $1.group)! }
            if $0.moonWashed != $1.moonWashed { return !$0.moonWashed }
            if fitOrder[$0.fit]! != fitOrder[$1.fit]! { return fitOrder[$0.fit]! < fitOrder[$1.fit]! }
            if $0.peakAltDeg != $1.peakAltDeg { return $0.peakAltDeg > $1.peakAltDeg }
            return ($0.magnitude ?? 99) < ($1.magnitude ?? 99)
        }
    }

    /// Top three across groups, at most one per group, deep sky first.
    static func best(from ranked: [RankedTarget]) -> [RankedTarget] {
        var picked: [RankedTarget] = []
        for g in [TargetGroup.nebulae, .galaxies, .clusters, .planets] {
            if let t = ranked.first(where: { $0.group == g && !$0.moonWashed }) { picked.append(t) }
            if picked.count == 3 { break }
        }
        return picked
    }

    public static func plan(night: Night, forecast: Forecast, catalog: Catalog, constellations: [Constellation], site: Site, fov: FieldOfView, rule: GoRule) -> NightPlan {
        let dark = darkHours(forecast.hours, night: night)
        var windows: [ClearWindow] = []
        if let ds = night.darkStart, let de = night.darkEnd {
            windows = Planner.windows(hours: forecast.hours, darkStart: ds, darkEnd: de, rule: rule)
        }
        let primary = windows.max { $0.hours < $1.hours }
        let moonMid = Ephemeris.moon(at: primary?.midpoint ?? night.darkStart ?? night.sunset, site: site)
        var aboveFraction = 0.0
        if let ds = night.darkStart, let de = night.darkEnd {
            var t = ds, n = 0, up = 0
            while t <= de { n += 1; if Ephemeris.moon(at: t, site: site).position.altDeg > 0 { up += 1 }; t = t.addingTimeInterval(3600) }
            aboveFraction = n == 0 ? 0 : Double(up) / Double(n)
        }
        let darkness: (Date, Date)? = (night.darkStart != nil && night.darkEnd != nil) ? (night.darkStart!, night.darkEnd!) : nil
        let score = Planner.score(ScoreInputs(darkHours: dark, windows: windows, darkness: darkness,
                                              moonIllumination: moonMid.illumination, moonAboveFraction: aboveFraction))
        let targets = primary.map { rank(catalog: catalog, constellations: constellations, window: $0, site: site, fov: fov, rule: rule) } ?? []
        return NightPlan(night: night, windows: windows, primary: primary, score: score, qualifies: primary != nil,
                         moonIllumination: moonMid.illumination, moonRise: moonMid.rise, moonSet: moonMid.set,
                         darkHours: dark, targets: targets, best: best(from: targets), seeingAvailable: dark.contains { $0.seeing != nil })
    }
}
```

Also add `Codable` to `Night` in Ephemeris.swift: `public struct Night: Codable, Equatable, Sendable`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all PlannerRank tests pass. `ranksNorthAmericaNebulaOnASeptemberNight` takes a few seconds (13,000 objects × 9 samples); that is acceptable for a nightly computation. If it exceeds 10 s, pre-filter objects by declination (`decDeg > site.latitude - 90 + rule.minAltitudeDeg` for the northern hemisphere and the mirror for southern) before tracking.

- [ ] **Step 5: Commit**

```bash
git add Sources/SkyCore/Planner.swift Sources/SkyCore/Ephemeris.swift Tests/SkyCoreTests/PlannerRankTests.swift
git commit -m "feat(skycore): target ranking, frame fit and NightPlan"
```

---
### Task 7: Events — meteor showers, eclipses, conjunctions

**Files:**
- Create: `Sources/SkyCore/Resources/events/meteor-showers.json`, `Sources/SkyCore/Events.swift`
- Test: `Tests/SkyCoreTests/EventsTests.swift`

**Interfaces:**
- Consumes: `Night`, `Site`, `Ephemeris.moon/planet/separationDeg/nextLunarEclipse/nextLocalSolarEclipse`.
- Produces:
  - `public struct MeteorShower: Codable, Equatable, Sendable, Identifiable { id, name, startMonth, startDay, endMonth, endDay, peakMonth, peakDay, zhr, raHours, decDeg, parent, velocityKms }`
  - `public enum MeteorShowers { static func bundled() throws -> [MeteorShower]; static func active(on: Date, calendar: Calendar, showers:) -> [MeteorShower]; static func isPeak(_:on:calendar:) -> Bool }`
  - `public enum SkyEventKind: String, Codable, Sendable { meteorShower, lunarEclipse, solarEclipse, conjunction, comet, issPass }`
  - `public struct SkyEvent: Codable, Equatable, Sendable, Identifiable { id, kind, title, detail, time: Date, endTime: Date?, raHours: Double?, decDeg: Double? }`
  - `public enum Events { static func showers(night:site:showers:) -> [SkyEvent]; static func eclipses(after:site:withinDays:) -> [SkyEvent]; static func conjunctions(at:site:maxSeparationDeg:) -> [SkyEvent] }`

- [ ] **Step 1: Write the shower data file**

`Sources/SkyCore/Resources/events/meteor-showers.json` (dates and radiants from the IMO-derived table on Wikipedia's list of meteor showers, verified 2026-09-23):

```json
[
  {"id":"qua","name":"Quadrantids","startMonth":12,"startDay":28,"endMonth":1,"endDay":12,"peakMonth":1,"peakDay":3,"zhr":80,"raHours":15.3,"decDeg":49,"parent":"(196256) 2003 EH1","velocityKms":41},
  {"id":"lyr","name":"Lyrids","startMonth":4,"startDay":14,"endMonth":4,"endDay":30,"peakMonth":4,"peakDay":22,"zhr":18,"raHours":18.1,"decDeg":34,"parent":"C/1861 G1 (Thatcher)","velocityKms":49},
  {"id":"eta","name":"Eta Aquariids","startMonth":4,"startDay":19,"endMonth":5,"endDay":28,"peakMonth":5,"peakDay":6,"zhr":50,"raHours":22.5,"decDeg":-1,"parent":"1P/Halley","velocityKms":66},
  {"id":"sda","name":"Southern Delta Aquariids","startMonth":7,"startDay":12,"endMonth":8,"endDay":23,"peakMonth":7,"peakDay":31,"zhr":25,"raHours":22.7,"decDeg":-16,"parent":"P/2008 Y12 (SOHO)","velocityKms":41},
  {"id":"per","name":"Perseids","startMonth":7,"startDay":17,"endMonth":8,"endDay":24,"peakMonth":8,"peakDay":13,"zhr":100,"raHours":3.2,"decDeg":58,"parent":"109P/Swift-Tuttle","velocityKms":59},
  {"id":"dra","name":"October Draconids","startMonth":10,"startDay":6,"endMonth":10,"endDay":10,"peakMonth":10,"peakDay":9,"zhr":5,"raHours":17.5,"decDeg":54,"parent":"21P/Giacobini-Zinner","velocityKms":20},
  {"id":"ori","name":"Orionids","startMonth":10,"startDay":2,"endMonth":11,"endDay":7,"peakMonth":10,"peakDay":21,"zhr":20,"raHours":6.3,"decDeg":16,"parent":"1P/Halley","velocityKms":66},
  {"id":"sta","name":"Southern Taurids","startMonth":9,"startDay":20,"endMonth":11,"endDay":20,"peakMonth":11,"peakDay":5,"zhr":7,"raHours":3.5,"decDeg":15,"parent":"2P/Encke","velocityKms":27},
  {"id":"nta","name":"Northern Taurids","startMonth":10,"startDay":20,"endMonth":12,"endDay":10,"peakMonth":11,"peakDay":12,"zhr":5,"raHours":3.9,"decDeg":22,"parent":"2004 TG10","velocityKms":29},
  {"id":"leo","name":"Leonids","startMonth":11,"startDay":6,"endMonth":11,"endDay":30,"peakMonth":11,"peakDay":17,"zhr":15,"raHours":10.1,"decDeg":22,"parent":"55P/Tempel-Tuttle","velocityKms":71},
  {"id":"gem","name":"Geminids","startMonth":12,"startDay":4,"endMonth":12,"endDay":20,"peakMonth":12,"peakDay":14,"zhr":150,"raHours":7.5,"decDeg":33,"parent":"3200 Phaethon","velocityKms":35},
  {"id":"urs","name":"Ursids","startMonth":12,"startDay":17,"endMonth":12,"endDay":26,"peakMonth":12,"peakDay":22,"zhr":10,"raHours":14.5,"decDeg":76,"parent":"8P/Tuttle","velocityKms":33}
]
```

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

private let site = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)

@Test func bundledShowersLoad() throws {
    let s = try MeteorShowers.bundled()
    #expect(s.count == 12)
    #expect(s.contains { $0.id == "gem" && $0.zhr == 150 })
}

@Test func activeShowersOnSeptember23IncludeSouthernTaurids() throws {
    let s = try MeteorShowers.bundled()
    let active = MeteorShowers.active(on: utc(2026, 9, 23, 12, 0), calendar: site.calendar, showers: s)
    #expect(active.map(\.id) == ["sta"])
}

@Test func quadrantidsSpanTheNewYear() throws {
    let s = try MeteorShowers.bundled()
    #expect(MeteorShowers.active(on: utc(2026, 12, 30, 12, 0), calendar: site.calendar, showers: s).contains { $0.id == "qua" })
    #expect(MeteorShowers.active(on: utc(2027, 1, 2, 12, 0), calendar: site.calendar, showers: s).contains { $0.id == "qua" })
    #expect(!MeteorShowers.active(on: utc(2027, 1, 20, 12, 0), calendar: site.calendar, showers: s).contains { $0.id == "qua" })
}

@Test func peakDetection() throws {
    let gem = try #require(try MeteorShowers.bundled().first { $0.id == "gem" })
    #expect(MeteorShowers.isPeak(gem, on: utc(2026, 12, 14, 12, 0), calendar: site.calendar))
    #expect(!MeteorShowers.isPeak(gem, on: utc(2026, 12, 10, 12, 0), calendar: site.calendar))
}

@Test func showerEventsCarryRadiantAndTitle() throws {
    let night = try Ephemeris.night(localDate: utc(2026, 12, 14, 12, 0), site: site)
    let ev = Events.showers(night: night, site: site, showers: try MeteorShowers.bundled())
    let gem = try #require(ev.first { $0.id == "shower-gem" })
    #expect(gem.kind == .meteorShower)
    #expect(gem.title.contains("Geminids"))
    #expect(gem.detail.contains("peak"))
    #expect(gem.raHours == 7.5)
}

@Test func eclipseEventsWithinAYearExist() {
    let ev = Events.eclipses(after: utc(2026, 9, 23, 0, 0), site: site, withinDays: 400)
    #expect(ev.contains { $0.kind == .lunarEclipse })
}

@Test func conjunctionsAreSymmetricAndBounded() {
    let ev = Events.conjunctions(at: utc(2026, 9, 23, 23, 0), site: site, maxSeparationDeg: 180)
    // 7 planets + Moon = 8 bodies -> 28 pairs
    #expect(ev.count == 28)
    let tight = Events.conjunctions(at: utc(2026, 9, 23, 23, 0), site: site, maxSeparationDeg: 3)
    #expect(tight.count <= 28)
    #expect(tight.allSatisfy { $0.kind == .conjunction })
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'MeteorShowers' in scope`.

- [ ] **Step 4: Implement Events.swift**

```swift
import Foundation

public struct MeteorShower: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let startMonth: Int, startDay: Int, endMonth: Int, endDay: Int, peakMonth: Int, peakDay: Int
    public let zhr: Int
    public let raHours: Double
    public let decDeg: Double
    public let parent: String
    public let velocityKms: Int
}

public enum MeteorShowers {
    public static func bundled() throws -> [MeteorShower] {
        guard let url = Bundle.module.url(forResource: "meteor-showers", withExtension: "json", subdirectory: "Resources/events") else {
            throw CatalogError.missingResource("meteor-showers")
        }
        return try JSONDecoder().decode([MeteorShower].self, from: Data(contentsOf: url))
    }

    /// Day-of-year comparison that wraps across the new year.
    static func inRange(month: Int, day: Int, shower s: MeteorShower) -> Bool {
        let d = month * 100 + day, a = s.startMonth * 100 + s.startDay, b = s.endMonth * 100 + s.endDay
        return a <= b ? (d >= a && d <= b) : (d >= a || d <= b)
    }

    public static func active(on date: Date, calendar: Calendar, showers: [MeteorShower]) -> [MeteorShower] {
        let c = calendar.dateComponents([.month, .day], from: date)
        return showers.filter { inRange(month: c.month!, day: c.day!, shower: $0) }
    }

    public static func isPeak(_ s: MeteorShower, on date: Date, calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: date)
        return c.month == s.peakMonth && c.day == s.peakDay
    }
}

public enum SkyEventKind: String, Codable, Sendable { case meteorShower, lunarEclipse, solarEclipse, conjunction, comet, issPass }

public struct SkyEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: SkyEventKind
    public let title: String
    public let detail: String
    public let time: Date
    public let endTime: Date?
    public let raHours: Double?
    public let decDeg: Double?
    public init(id: String, kind: SkyEventKind, title: String, detail: String, time: Date, endTime: Date?, raHours: Double?, decDeg: Double?) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.time = time; self.endTime = endTime
        self.raHours = raHours; self.decDeg = decDeg
    }
}

public enum Events {
    public static func showers(night: Night, site: Site, showers: [MeteorShower]) -> [SkyEvent] {
        let cal = site.calendar
        return MeteorShowers.active(on: night.localDate, calendar: cal, showers: showers).map { s in
            let peakTonight = MeteorShowers.isPeak(s, on: night.localDate, calendar: cal)
                || MeteorShowers.isPeak(s, on: cal.date(byAdding: .day, value: 1, to: night.localDate)!, calendar: cal)
            let detail = peakTonight ? "At peak tonight, ZHR \(s.zhr)" : "Active, peak \(s.peakDay)/\(s.peakMonth), ZHR \(s.zhr)"
            return SkyEvent(id: "shower-\(s.id)", kind: .meteorShower, title: s.name, detail: detail,
                            time: night.darkStart ?? night.sunset, endTime: night.darkEnd, raHours: s.raHours, decDeg: s.decDeg)
        }
    }

    public static func eclipses(after date: Date, site: Site, withinDays: Int) -> [SkyEvent] {
        let limit = date.addingTimeInterval(Double(withinDays) * 86_400)
        var out: [SkyEvent] = []
        if let l = Ephemeris.nextLunarEclipse(after: date), l.peak <= limit {
            out.append(SkyEvent(id: "lunar-\(Int(l.peak.timeIntervalSince1970))", kind: .lunarEclipse,
                                title: "\(l.kind.rawValue.capitalized) lunar eclipse", detail: "Peak obscuration \(Int((l.obscuration * 100).rounded()))%",
                                time: l.peak, endTime: nil, raHours: nil, decDeg: nil))
        }
        if let s = Ephemeris.nextLocalSolarEclipse(after: date, site: site), s.peak <= limit {
            out.append(SkyEvent(id: "solar-\(Int(s.peak.timeIntervalSince1970))", kind: .solarEclipse,
                                title: "\(s.kind.rawValue.capitalized) solar eclipse from \(site.name)", detail: "Peak obscuration \(Int((s.obscuration * 100).rounded()))%",
                                time: s.peak, endTime: s.partialEnd, raHours: nil, decDeg: nil))
        }
        return out
    }

    /// Pairs among the Moon and the seven planets closer than `maxSeparationDeg` at `date`.
    public static func conjunctions(at date: Date, site: Site, maxSeparationDeg: Double) -> [SkyEvent] {
        var bodies: [(String, BodyPosition)] = Planet.allCases.map { ($0.displayName, Ephemeris.planet($0, at: date, site: site)) }
        bodies.append(("Moon", Ephemeris.moon(at: date, site: site).position))
        var out: [SkyEvent] = []
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let (a, pa) = bodies[i], (b, pb) = bodies[j]
                let sep = Ephemeris.separationDeg(ra1Hours: pa.raHours, dec1Deg: pa.decDeg, ra2Hours: pb.raHours, dec2Deg: pb.decDeg)
                guard sep <= maxSeparationDeg else { continue }
                out.append(SkyEvent(id: "conj-\(a)-\(b)", kind: .conjunction, title: "\(a) near \(b)",
                                    detail: String(format: "%.1f° apart", sep), time: date, endTime: nil,
                                    raHours: pa.raHours, decDeg: pa.decDeg))
            }
        }
        return out.sorted { $0.detail < $1.detail }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all Events tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SkyCore/Events.swift Sources/SkyCore/Resources/events Tests/SkyCoreTests/EventsTests.swift
git commit -m "feat(skycore): meteor showers, eclipses and conjunction events"
```

---

### Task 8: Comets (MPC elements, local propagation)

**Files:**
- Create: `Sources/SkyCore/Comets.swift`, `Tests/SkyCoreTests/Fixtures/comets.json`
- Test: `Tests/SkyCoreTests/CometTests.swift`

**Interfaces:**
- Consumes: `astro_time_t`, `Astronomy_HelioVector`.
- Produces:
  - `public struct CometElements: Codable, Equatable, Sendable { orbitType, designation, q, e, periDeg, nodeDeg, incDeg, perihelionYear, perihelionMonth, perihelionDay: Double, epochYear, epochMonth, epochDay, h, g }` with `CodingKeys` matching the MPC names.
  - `public struct CometPosition: Equatable, Sendable { raHours, decDeg, magnitude, deltaAU, rAU }`
  - `public enum Comets { static func decode(_ data: Data) throws -> [CometElements]; static func position(_:at:) -> CometPosition?; static func url: URL }`

- [ ] **Step 1: Write the fixture**

`Tests/SkyCoreTests/Fixtures/comets.json` — the 2P/Encke record as served on 2026-09-23 plus the interstellar 2I record that shares `Comet_num` 2:

```json
[
  {"Comet_num": 2, "Orbit_type": "P", "Year_of_perihelion": 2027, "Month_of_perihelion": 2, "Day_of_perihelion": 10.2278, "Perihelion_dist": 0.338612, "e": 0.847316, "Peri": 187.2869, "Node": 334.0195, "i": 11.3479, "Epoch_year": 2026, "Epoch_month": 9, "Epoch_day": 23, "H": 14.3, "G": 4.0, "Designation_and_name": "2P/Encke", "Ref": "MPC xxxxx"},
  {"Comet_num": 2, "Orbit_type": "I", "Year_of_perihelion": 2019, "Month_of_perihelion": 12, "Day_of_perihelion": 9.0572, "Perihelion_dist": 1.997724, "e": 3.345952, "Peri": 209.2911, "Node": 307.8024, "i": 44.2624, "Epoch_year": 2025, "Epoch_month": 11, "Epoch_day": 21, "H": 11.0, "G": 4.0, "Designation_and_name": "2I/Borisov", "Ref": "MPEC 2025"},
  {"Orbit_type": "C", "Provisional_packed_desig": "J42E00A", "Year_of_perihelion": 2028, "Month_of_perihelion": 9, "Day_of_perihelion": 13.9706, "Perihelion_dist": 1.277687, "e": 0.934892, "Peri": 335.558, "Node": 172.3208, "i": 37.8738, "Epoch_year": 2026, "Epoch_month": 9, "Epoch_day": 23, "H": 13.5, "G": 4.0, "Designation_and_name": "C/1942 EA (Vaisala)", "Ref": "MPEC 2026"}
]
```

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

@Test func decodesMpcRecords() throws {
    let comets = try Comets.decode(try fixture("comets.json"))
    #expect(comets.count == 3)
    let encke = try #require(comets.first { $0.designation == "2P/Encke" })
    #expect(encke.orbitType == "P" && abs(encke.q - 0.338612) < 1e-9 && encke.perihelionDay == 10.2278)
}

// Oracle: JPL Horizons, 2P/Encke, geocentric, 2026-09-23 00:00 UT: RA 16.36366°, Dec 20.44533°, delta 1.28624917 AU, APmag 17.815.
@Test func enckeMatchesHorizonsAtEpoch() throws {
    let encke = try #require(try Comets.decode(try fixture("comets.json")).first { $0.designation == "2P/Encke" })
    let p = try #require(Comets.position(encke, at: utc(2026, 9, 23, 0, 0)))
    #expect(abs(p.raHours * 15 - 16.36366) < 0.5)
    #expect(abs(p.decDeg - 20.44533) < 0.5)
    #expect(abs(p.deltaAU - 1.28625) < 0.02)
    #expect(abs(p.magnitude - 17.8) < 1.5)
}

@Test func hyperbolicOrbitPropagates() throws {
    let borisov = try #require(try Comets.decode(try fixture("comets.json")).first { $0.designation == "2I/Borisov" })
    let p = try #require(Comets.position(borisov, at: utc(2026, 9, 23, 0, 0)))
    #expect(p.rAU > 10)          // long gone
    #expect(p.magnitude > 20)
}

@Test func nearParabolicDoesNotCrash() throws {
    var c = try #require(try Comets.decode(try fixture("comets.json")).first { $0.designation.hasPrefix("C/1942") })
    c.e = 1.0
    #expect(Comets.position(c, at: utc(2026, 9, 23, 0, 0)) != nil)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'Comets' in scope`.

- [ ] **Step 4: Implement Comets.swift**

```swift
import CAstronomyEngine
import Foundation

public struct CometElements: Codable, Equatable, Sendable {
    public var orbitType: String
    public var designation: String
    public var q: Double
    public var e: Double
    public var periDeg: Double
    public var nodeDeg: Double
    public var incDeg: Double
    public var perihelionYear: Int
    public var perihelionMonth: Int
    public var perihelionDay: Double
    public var epochYear: Int?
    public var epochMonth: Int?
    public var epochDay: Int?
    public var h: Double?
    public var g: Double?

    enum CodingKeys: String, CodingKey {
        case orbitType = "Orbit_type", designation = "Designation_and_name", q = "Perihelion_dist", e
        case periDeg = "Peri", nodeDeg = "Node", incDeg = "i"
        case perihelionYear = "Year_of_perihelion", perihelionMonth = "Month_of_perihelion", perihelionDay = "Day_of_perihelion"
        case epochYear = "Epoch_year", epochMonth = "Epoch_month", epochDay = "Epoch_day", h = "H", g = "G"
    }

    var perihelionDate: Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let whole = Int(perihelionDay.rounded(.down))
        let d = cal.date(from: DateComponents(year: perihelionYear, month: perihelionMonth, day: whole))!
        return d.addingTimeInterval((perihelionDay - Double(whole)) * 86_400)
    }
}

public struct CometPosition: Equatable, Sendable {
    public let raHours: Double
    public let decDeg: Double
    public let magnitude: Double
    public let deltaAU: Double
    public let rAU: Double
}

public enum Comets {
    public static let url = URL(string: "https://www.minorplanetcenter.net/Extended_Files/cometels.json.gz")!

    public static func decode(_ data: Data) throws -> [CometElements] {
        try JSONDecoder().decode([CometElements].self, from: data)
    }

    private static let k = 0.017_202_098_95          // Gaussian gravitational constant, rad/day
    private static let obliquity = 23.439_291_1 * Double.pi / 180

    /// Heliocentric distance r and true anomaly ν at `dt` days from perihelion.
    static func anomaly(q: Double, e: Double, dt: Double) -> (r: Double, nu: Double) {
        if abs(e - 1) < 1e-6 {
            let w = 1.5 * k / sqrt(2 * q * q * q) * dt
            let y = cbrt(w + sqrt(w * w + 1))
            let s = y - 1 / y
            return (q * (1 + s * s), 2 * atan(s))
        }
        if e < 1 {
            let a = q / (1 - e)
            let m = k / pow(a, 1.5) * dt
            var ecc = m
            for _ in 0..<50 { ecc -= (ecc - e * sin(ecc) - m) / (1 - e * cos(ecc)) }
            let nu = 2 * atan2(sqrt(1 + e) * sin(ecc / 2), sqrt(1 - e) * cos(ecc / 2))
            return (a * (1 - e * cos(ecc)), nu)
        }
        let a = q / (e - 1)
        let m = k / pow(a, 1.5) * dt
        var hh = asinh(m / e)
        for _ in 0..<50 { hh -= (e * sinh(hh) - hh - m) / (e * cosh(hh) - 1) }
        let nu = 2 * atan2(sqrt(e + 1) * sinh(hh / 2), sqrt(e - 1) * cosh(hh / 2))
        return (a * (e * cosh(hh) - 1), nu)
    }

    public static func position(_ c: CometElements, at date: Date) -> CometPosition? {
        let dt = date.timeIntervalSince(c.perihelionDate) / 86_400
        let (r, nu) = anomaly(q: c.q, e: c.e, dt: dt)
        guard r.isFinite, nu.isFinite else { return nil }
        let d2r = Double.pi / 180
        let w = c.periDeg * d2r, om = c.nodeDeg * d2r, inc = c.incDeg * d2r
        let u = w + nu
        // heliocentric ecliptic J2000
        let x = r * (cos(om) * cos(u) - sin(om) * sin(u) * cos(inc))
        let y = r * (sin(om) * cos(u) + cos(om) * sin(u) * cos(inc))
        let z = r * (sin(u) * sin(inc))
        // ecliptic -> equatorial J2000
        let xe = x
        let ye = y * cos(obliquity) - z * sin(obliquity)
        let ze = y * sin(obliquity) + z * cos(obliquity)
        let earth = Astronomy_HelioVector(BODY_EARTH, astro_time_t(date))
        guard earth.status == ASTRO_SUCCESS else { return nil }
        let gx = xe - earth.x, gy = ye - earth.y, gz = ze - earth.z
        let delta = sqrt(gx * gx + gy * gy + gz * gz)
        var ra = atan2(gy, gx) / d2r / 15
        if ra < 0 { ra += 24 }
        let dec = asin(gz / delta) / d2r
        let mag = (c.h ?? 20) + 5 * log10(delta) + 2.5 * (c.g ?? 4) * log10(r)
        return CometPosition(raHours: ra, decDeg: dec, magnitude: mag, deltaAU: delta, rAU: r)
    }

    /// Comets brighter than `limit` at `date`, brightest first.
    public static func bright(_ comets: [CometElements], at date: Date, limit: Double = 12) -> [(CometElements, CometPosition)] {
        comets.compactMap { c in position(c, at: date).map { (c, $0) } }
            .filter { $0.1.magnitude <= limit }
            .sorted { $0.1.magnitude < $1.1.magnitude }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all Comet tests pass. If `enckeMatchesHorizonsAtEpoch` is off by roughly 180° in RA, the Earth vector sign is wrong (geocentric = comet − Earth). If off by a few degrees, check that `Peri`, `Node`, `i` are used in degrees.

- [ ] **Step 6: Commit**

```bash
git add Sources/SkyCore/Comets.swift Tests/SkyCoreTests/CometTests.swift Tests/SkyCoreTests/Fixtures/comets.json
git commit -m "feat(skycore): MPC comet elements and local orbit propagation"
```

---

### Task 9: ISS passes (SatelliteKit)

**Files:**
- Create: `Sources/SkyCore/Satellites.swift`, `Tests/SkyCoreTests/Fixtures/iss.tle`
- Test: `Tests/SkyCoreTests/SatelliteTests.swift`

**Interfaces:**
- Consumes: SatelliteKit `Elements(_:_:_:) throws`, `Satellite(withTLE:)`, `position(julianDays:) throws -> Vector`, `topPosition(julianDays:observer:) throws -> AziEleDst`, `LatLonAlt(lat, lon, altKm)`, `Date.julianDate`; `Astronomy_GeoVector`, `Ephemeris.sunAltitude`.
- Produces:
  - `public struct TLE: Codable, Equatable, Sendable { line0, line1, line2 }`
  - `public struct SatellitePass: Codable, Equatable, Sendable { rise: Date, peak: Date, set: Date, maxElevationDeg: Double, peakAzimuthDeg: Double }`
  - `public enum Satellites { static let issURL: URL; static func parseTLE(_ text: String) throws -> TLE; static func passes(tle:site:from:to:minPeakElevation:stepSeconds:) throws -> [SatellitePass] }`

- [ ] **Step 1: Create the fixture**

```bash
curl -sS 'https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=TLE' -o Tests/SkyCoreTests/Fixtures/iss.tle
cat Tests/SkyCoreTests/Fixtures/iss.tle
```

Expected: three lines beginning `ISS (ZARYA)`, `1 25544U`, `2 25544`. Record the epoch day from line 1 (columns 19–32) in the test comment.

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

private let site = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)

private func issTLE() throws -> TLE {
    try Satellites.parseTLE(String(decoding: try fixture("iss.tle"), as: UTF8.self))
}

private func epochDate(_ tle: TLE) -> Date {
    // columns 19-32 of line 1: YYDDD.DDDDDDDD
    let s = tle.line1
    let yy = Int(s[s.index(s.startIndex, offsetBy: 18)..<s.index(s.startIndex, offsetBy: 20)])!
    let doy = Double(s[s.index(s.startIndex, offsetBy: 20)..<s.index(s.startIndex, offsetBy: 32)].trimmingCharacters(in: .whitespaces))!
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    let jan1 = cal.date(from: DateComponents(year: 2000 + yy, month: 1, day: 1))!
    return jan1.addingTimeInterval((doy - 1) * 86_400)
}

@Test func parsesThreeLineTLE() throws {
    let t = try issTLE()
    #expect(t.line0.hasPrefix("ISS"))
    #expect(t.line1.hasPrefix("1 25544"))
    #expect(t.line2.hasPrefix("2 25544"))
}

@Test func rejectsMalformedTLE() {
    #expect(throws: (any Error).self) { try Satellites.parseTLE("nonsense") }
}

@Test func passesAreWellFormedAndOrdered() throws {
    let tle = try issTLE()
    let from = epochDate(tle)
    let to = from.addingTimeInterval(3 * 86_400)
    let passes = try Satellites.passes(tle: tle, site: site, from: from, to: to, minPeakElevation: 0, stepSeconds: 30)
    #expect(passes.count >= 3)                       // ISS crosses a 53° site several times in three days
    for p in passes {
        #expect(p.rise < p.peak && p.peak < p.set)
        #expect(p.set.timeIntervalSince(p.rise) < 15 * 60)
        #expect(p.maxElevationDeg >= 0 && p.maxElevationDeg <= 90)
        #expect(p.peakAzimuthDeg >= 0 && p.peakAzimuthDeg < 360)
    }
    #expect(passes == passes.sorted { $0.rise < $1.rise })
}

@Test func higherThresholdReturnsSubset() throws {
    let tle = try issTLE()
    let from = epochDate(tle), to = from.addingTimeInterval(3 * 86_400)
    let all = try Satellites.passes(tle: tle, site: site, from: from, to: to, minPeakElevation: 0, stepSeconds: 30)
    let high = try Satellites.passes(tle: tle, site: site, from: from, to: to, minPeakElevation: 30, stepSeconds: 30)
    #expect(high.count <= all.count)
    #expect(high.allSatisfy { $0.maxElevationDeg >= 30 })
}

@Test func visiblePassesRequireDarkObserverAndSunlitSatellite() throws {
    let tle = try issTLE()
    let from = epochDate(tle), to = from.addingTimeInterval(3 * 86_400)
    let visible = try Satellites.visiblePasses(tle: tle, site: site, from: from, to: to, minPeakElevation: 0)
    let all = try Satellites.passes(tle: tle, site: site, from: from, to: to, minPeakElevation: 0, stepSeconds: 30)
    #expect(visible.count <= all.count)
    for p in visible { #expect(Ephemeris.sunAltitude(at: p.peak, site: site) < -6) }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'Satellites' in scope`.

- [ ] **Step 4: Implement Satellites.swift**

```swift
import CAstronomyEngine
import Foundation
import SatelliteKit

public struct TLE: Codable, Equatable, Sendable {
    public let line0: String
    public let line1: String
    public let line2: String
    public init(line0: String, line1: String, line2: String) { self.line0 = line0; self.line1 = line1; self.line2 = line2 }
}

public struct SatellitePass: Codable, Equatable, Sendable {
    public let rise: Date
    public let peak: Date
    public let set: Date
    public let maxElevationDeg: Double
    public let peakAzimuthDeg: Double
}

public enum SatelliteError: Error { case malformedTLE }

public enum Satellites {
    public static let issURL = URL(string: "https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=TLE")!

    public static func parseTLE(_ text: String) throws -> TLE {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 3, lines[1].hasPrefix("1 "), lines[2].hasPrefix("2 ") else { throw SatelliteError.malformedTLE }
        return TLE(line0: lines[0], line1: lines[1], line2: lines[2])
    }

    /// Passes above the horizon between `from` and `to`, peak elevation at least `minPeakElevation` degrees.
    public static func passes(tle: TLE, site: Site, from: Date, to: Date, minPeakElevation: Double = 30, stepSeconds: TimeInterval = 30) throws -> [SatellitePass] {
        let sat = Satellite(withTLE: try Elements(tle.line0, tle.line1, tle.line2))
        let observer = LatLonAlt(site.latitude, site.longitude, site.elevationM / 1000)
        var out: [SatellitePass] = []
        var t = from
        var rise: Date? = nil
        var peakEl = -90.0, peakAz = 0.0, peakT = from
        while t <= to {
            let top = try sat.topPosition(julianDays: t.julianDate, observer: observer)
            if top.elev > 0 {
                if rise == nil { rise = t; peakEl = -90 }
                if top.elev > peakEl { peakEl = top.elev; peakAz = top.azim; peakT = t }
            } else if let r = rise {
                if peakEl >= minPeakElevation {
                    out.append(SatellitePass(rise: r, peak: peakT, set: t, maxElevationDeg: peakEl, peakAzimuthDeg: peakAz))
                }
                rise = nil
            }
            t = t.addingTimeInterval(stepSeconds)
        }
        return out
    }

    /// True when the satellite at `date` is outside Earth's cylindrical shadow.
    static func isSunlit(_ sat: Satellite, at date: Date) throws -> Bool {
        let p = try sat.position(julianDays: date.julianDate)          // km, ECI (TEME; precession vs EQJ ignored)
        let sun = Astronomy_GeoVector(BODY_SUN, astro_time_t(date), NO_ABERRATION)
        guard sun.status == ASTRO_SUCCESS else { return true }
        let n = sqrt(sun.x * sun.x + sun.y * sun.y + sun.z * sun.z)
        let sx = sun.x / n, sy = sun.y / n, sz = sun.z / n
        let along = p.x * sx + p.y * sy + p.z * sz
        if along > 0 { return true }
        let px = p.x - along * sx, py = p.y - along * sy, pz = p.z - along * sz
        return sqrt(px * px + py * py + pz * pz) > 6371
    }

    /// Passes the observer can see: observer past civil dusk (Sun below −6°) and satellite sunlit at peak.
    public static func visiblePasses(tle: TLE, site: Site, from: Date, to: Date, minPeakElevation: Double = 30) throws -> [SatellitePass] {
        let sat = Satellite(withTLE: try Elements(tle.line0, tle.line1, tle.line2))
        return try passes(tle: tle, site: site, from: from, to: to, minPeakElevation: minPeakElevation, stepSeconds: 30).filter { p in
            Ephemeris.sunAltitude(at: p.peak, site: site) < -6 && (try isSunlit(sat, at: p.peak))
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all Satellite tests pass. If `topPosition` elevations never exceed 0, print one value; a swapped lat/lon order in `LatLonAlt` is the usual cause (it is lat, lon, altitude in km).

- [ ] **Step 6: Commit**

```bash
git add Sources/SkyCore/Satellites.swift Tests/SkyCoreTests/SatelliteTests.swift Tests/SkyCoreTests/Fixtures/iss.tle
git commit -m "feat(skycore): ISS pass prediction with SatelliteKit"
```

---
### Task 10: Copy table and alert state machine

**Files:**
- Create: `Sources/SkyCore/Copy.swift`, `Sources/SkyCore/Alerts.swift`
- Test: `Tests/SkyCoreTests/AlertTests.swift`

**Interfaces:**
- Consumes: `NightPlan`, `Night`, `ClearWindow`, `RankedTarget`.
- Produces:
  - `public enum Flavour: String, Codable, Sendable { watch, plain }`
  - `public struct Copy: Sendable { init(flavour:); refresh, siteNoun, goTitle(windowStart:formatter:), cancelTitle, noWindow, offlineSince(_:), headsUpTitle(windowStart:hours:), tomorrowTitle(hours:), notificationBody(plan:) }`
  - `public struct AlertSettings: Codable, Equatable, Sendable { headsUp = true, tomorrowPreview = true, preWindowMinutes = 30, cancelOnDowngrade = true, quietStartHour = 0, quietEndHour = 7 }`
  - `public struct AlertState: Codable, Equatable, Sendable { nightKey: String, stage: Stage; enum Stage: String, Codable { idle, headsUpSent, goSent, cancelled, done } }`
  - `public struct AlertNotification: Equatable, Sendable { kind: Kind, title: String, body: String; enum Kind { headsUp, tomorrowPreview, go, cancel } }`
  - `public enum AlertEngine { static func step(now:tonight:tomorrow:state:settings:forecastFetchedAt:site:copy:) -> (notification: AlertNotification?, state: AlertState) ; static func inQuietHours(_:site:settings:) -> Bool }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

private let site = Site(name: "Sheffield", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)
private let copy = Copy(flavour: .watch)
private let settings = AlertSettings()

/// Build a plan by hand with a given window and qualifying flag.
private func plan(night: Night, window: ClearWindow?) -> NightPlan {
    NightPlan(night: night, windows: window.map { [$0] } ?? [], primary: window, score: window == nil ? 10 : 80, qualifies: window != nil,
              moonIllumination: 0.3, moonRise: nil, moonSet: nil, darkHours: [], targets: [], best: [], seeingAvailable: false)
}

private func fixtures() throws -> (Night, NightPlan, NightPlan, NightPlan) {
    let night = try Ephemeris.night(localDate: utc(2026, 9, 23, 12, 0), site: site)
    let window = ClearWindow(start: night.darkStart!.addingTimeInterval(3600), end: night.darkStart!.addingTimeInterval(5 * 3600))
    let good = plan(night: night, window: window)
    let bad = plan(night: night, window: nil)
    let tomorrowNight = try Ephemeris.night(localDate: utc(2026, 9, 24, 12, 0), site: site)
    let tomorrowGood = plan(night: tomorrowNight, window: ClearWindow(start: tomorrowNight.darkStart!, end: tomorrowNight.darkStart!.addingTimeInterval(4 * 3600)))
    return (night, good, bad, tomorrowGood)
}

@Test func headsUpFiresOneHourBeforeSunsetOnly() throws {
    let (night, good, _, _) = try fixtures()
    let early = night.sunset.addingTimeInterval(-2 * 3600)
    let r0 = AlertEngine.step(now: early, tonight: good, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: early, site: site, copy: copy)
    #expect(r0.notification == nil && r0.state.stage == .idle)
    let due = night.sunset.addingTimeInterval(-3600 + 60)
    let r1 = AlertEngine.step(now: due, tonight: good, tomorrow: nil, state: r0.state, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r1.notification?.kind == .headsUp)
    #expect(r1.state.stage == .headsUpSent)
    let r2 = AlertEngine.step(now: due.addingTimeInterval(600), tonight: good, tomorrow: nil, state: r1.state, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r2.notification == nil)   // idempotent
}

@Test func goFiresThirtyMinutesBeforeWindow() throws {
    let (_, good, _, _) = try fixtures()
    let state = AlertState(nightKey: good.night.key, stage: .headsUpSent)
    let tooEarly = good.primary!.start.addingTimeInterval(-45 * 60)
    #expect(AlertEngine.step(now: tooEarly, tonight: good, tomorrow: nil, state: state, settings: settings, forecastFetchedAt: tooEarly, site: site, copy: copy).notification == nil)
    let due = good.primary!.start.addingTimeInterval(-29 * 60)
    let r = AlertEngine.step(now: due, tonight: good, tomorrow: nil, state: state, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r.notification?.kind == .go)
    #expect(r.state.stage == .goSent)
    #expect(r.notification!.title.hasPrefix("All's well"))
}

@Test func cancelAfterHeadsUpWhenForecastDrops() throws {
    let (_, _, bad, _) = try fixtures()
    let state = AlertState(nightKey: bad.night.key, stage: .headsUpSent)
    let now = bad.night.sunset
    let r = AlertEngine.step(now: now, tonight: bad, tomorrow: nil, state: state, settings: settings, forecastFetchedAt: now, site: site, copy: copy)
    #expect(r.notification?.kind == .cancel)
    #expect(r.state.stage == .cancelled)
    #expect(r.notification!.title.hasPrefix("Stand down"))
}

@Test func tomorrowPreviewWhenTonightFails() throws {
    let (night, _, bad, tomorrowGood) = try fixtures()
    let due = night.sunset.addingTimeInterval(-3000)
    let r = AlertEngine.step(now: due, tonight: bad, tomorrow: tomorrowGood, state: nil, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r.notification?.kind == .tomorrowPreview)
    #expect(r.state.stage == .done)
}

@Test func quietHoursDropButAdvance() throws {
    let (_, good, _, _) = try fixtures()
    // 02:00 local on the 24th is inside 00:00–07:00
    let cal = site.calendar
    let two = cal.date(bySettingHour: 2, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: good.night.localDate)!)!
    let late = plan(night: good.night, window: ClearWindow(start: two.addingTimeInterval(1200), end: two.addingTimeInterval(4 * 3600)))
    let state = AlertState(nightKey: late.night.key, stage: .headsUpSent)
    let r = AlertEngine.step(now: two, tonight: late, tomorrow: nil, state: state, settings: settings, forecastFetchedAt: two, site: site, copy: copy)
    #expect(r.notification == nil)
    #expect(r.state.stage == .goSent)
    #expect(AlertEngine.inQuietHours(two, site: site, settings: settings))
}

@Test func staleForecastSendsNothing() throws {
    let (night, good, _, _) = try fixtures()
    let due = night.sunset.addingTimeInterval(-3000)
    let r = AlertEngine.step(now: due, tonight: good, tomorrow: nil, state: nil, settings: settings, forecastFetchedAt: due.addingTimeInterval(-7 * 3600), site: site, copy: copy)
    #expect(r.notification == nil && r.state.stage == .idle)
}

@Test func newNightResetsState() throws {
    let (night, good, _, _) = try fixtures()
    let stale = AlertState(nightKey: "2026-09-22", stage: .done)
    let due = night.sunset.addingTimeInterval(-3000)
    let r = AlertEngine.step(now: due, tonight: good, tomorrow: nil, state: stale, settings: settings, forecastFetchedAt: due, site: site, copy: copy)
    #expect(r.state.nightKey == "2026-09-23")
    #expect(r.notification?.kind == .headsUp)
}

@Test func plainFlavourHasNoWatchPhrases() {
    let c = Copy(flavour: .plain)
    #expect(c.refresh == "Refresh")
    #expect(c.noWindow == "No clear window tonight.")
    #expect(!c.cancelTitle.contains("Stand down"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'AlertEngine' in scope`.

- [ ] **Step 3: Implement Copy.swift**

```swift
import Foundation

public enum Flavour: String, Codable, Sendable { case watch, plain }

/// Every flavoured string reads as ordinary English. Spec §6 is the only place new ones may be added.
public struct Copy: Sendable {
    public let flavour: Flavour
    public init(flavour: Flavour) { self.flavour = flavour }
    private var watch: Bool { flavour == .watch }

    public var refresh: String { watch ? "Patrol" : "Refresh" }
    public var siteNoun: String { watch ? "Beat" : "Site" }
    public var noWindow: String { watch ? "Nothing to see here. Move along." : "No clear window tonight." }
    public var cancelTitle: String { watch ? "Stand down. Clouds moving in" : "Cancelled. Clouds moving in" }
    public func offlineSince(_ time: String) -> String { watch ? "Off the beat since \(time)" : "Offline since \(time)" }
    public func goTitle(windowStart: String) -> String { watch ? "All's well. Clear from \(windowStart)" : "Clear from \(windowStart)" }
    public func headsUpTitle(windowStart: String, hours: Double) -> String {
        String(format: "Clear skies tonight from %@ · %.1f h", windowStart, hours)
    }
    public func tomorrowTitle(hours: Double) -> String { String(format: "Tomorrow night looks clear · %.1f h", hours) }

    public func notificationBody(plan: NightPlan, site: Site) -> String {
        var parts: [String] = []
        if let set = plan.moonSet { parts.append("Moon sets \(Copy.hhmm(set, site: site))") }
        else if plan.moonIllumination < 0.1 { parts.append("No Moon") }
        else { parts.append("Moon \(Int((plan.moonIllumination * 100).rounded()))%") }
        if !plan.best.isEmpty { parts.append(plan.best.map(\.name).joined(separator: ", ") + " well placed") }
        return parts.joined(separator: ". ") + "."
    }

    public static func hhmm(_ date: Date, site: Site) -> String {
        let f = DateFormatter(); f.timeZone = site.timeZone; f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_GB")
        return f.string(from: date)
    }

    public func scoreBand(_ score: Int) -> String {
        switch score { case 80...: "Excellent"; case 50..<80: "Fair"; case 20..<50: "Poor"; default: "Overcast" }
    }
}
```

- [ ] **Step 4: Implement Alerts.swift**

```swift
import Foundation

public struct AlertSettings: Codable, Equatable, Sendable {
    public var headsUp = true
    public var tomorrowPreview = true
    public var preWindowMinutes = 30
    public var cancelOnDowngrade = true
    public var quietStartHour = 0
    public var quietEndHour = 7
    public init() {}
}

public struct AlertState: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable { case idle, headsUpSent, goSent, cancelled, done }
    public var nightKey: String
    public var stage: Stage
    public init(nightKey: String, stage: Stage) { self.nightKey = nightKey; self.stage = stage }
}

public struct AlertNotification: Equatable, Sendable {
    public enum Kind: Sendable { case headsUp, tomorrowPreview, go, cancel }
    public let kind: Kind
    public let title: String
    public let body: String
}

public enum AlertEngine {
    static let staleAfter: TimeInterval = 6 * 3600

    public static func inQuietHours(_ date: Date, site: Site, settings: AlertSettings) -> Bool {
        let h = site.calendar.component(.hour, from: date)
        let a = settings.quietStartHour, b = settings.quietEndHour
        if a == b { return false }
        return a < b ? (h >= a && h < b) : (h >= a || h < b)
    }

    public static func step(now: Date, tonight: NightPlan, tomorrow: NightPlan?, state: AlertState?, settings: AlertSettings,
                            forecastFetchedAt: Date, site: Site, copy: Copy) -> (notification: AlertNotification?, state: AlertState) {
        var s = (state?.nightKey == tonight.night.key) ? state! : AlertState(nightKey: tonight.night.key, stage: .idle)
        guard now.timeIntervalSince(forecastFetchedAt) <= staleAfter else { return (nil, s) }

        let headsUpAt = tonight.night.sunset.addingTimeInterval(-3600)
        let goAt = tonight.primary?.start.addingTimeInterval(-Double(settings.preWindowMinutes) * 60)
        var note: AlertNotification? = nil

        func window(_ p: NightPlan) -> (String, Double) {
            (Copy.hhmm(p.primary!.start, site: site), p.primary!.hours)
        }

        switch s.stage {
        case .idle:
            if let g = goAt, tonight.qualifies, now >= g {
                let (start, _) = window(tonight)
                note = AlertNotification(kind: .go, title: copy.goTitle(windowStart: start), body: copy.notificationBody(plan: tonight, site: site))
                s.stage = .goSent
            } else if now >= headsUpAt {
                if tonight.qualifies, settings.headsUp {
                    let (start, hours) = window(tonight)
                    note = AlertNotification(kind: .headsUp, title: copy.headsUpTitle(windowStart: start, hours: hours), body: copy.notificationBody(plan: tonight, site: site))
                    s.stage = .headsUpSent
                } else if !tonight.qualifies, let t = tomorrow, t.qualifies, settings.tomorrowPreview {
                    note = AlertNotification(kind: .tomorrowPreview, title: copy.tomorrowTitle(hours: t.primary!.hours), body: copy.notificationBody(plan: t, site: site))
                    s.stage = .done
                } else if !tonight.qualifies, now >= tonight.night.sunset {
                    s.stage = .done
                }
            }
        case .headsUpSent, .cancelled:
            if !tonight.qualifies, s.stage == .headsUpSent, settings.cancelOnDowngrade {
                note = AlertNotification(kind: .cancel, title: copy.cancelTitle, body: copy.noWindow)
                s.stage = .cancelled
            } else if let g = goAt, tonight.qualifies, now >= g {
                let (start, _) = window(tonight)
                note = AlertNotification(kind: .go, title: copy.goTitle(windowStart: start), body: copy.notificationBody(plan: tonight, site: site))
                s.stage = .goSent
            }
        case .goSent:
            if !tonight.qualifies, settings.cancelOnDowngrade {
                note = AlertNotification(kind: .cancel, title: copy.cancelTitle, body: copy.noWindow)
                s.stage = .cancelled
            } else if let end = tonight.primary?.end, now >= end {
                s.stage = .done
            }
        case .done:
            break
        }

        if note != nil, inQuietHours(now, site: site, settings: settings) { note = nil }   // dropped, not deferred
        return (note, s)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all Alert tests pass. `cancelAfterHeadsUpWhenForecastDrops` runs at sunset (not quiet hours) so the cancel is delivered.

- [ ] **Step 6: Commit**

```bash
git add Sources/SkyCore/Copy.swift Sources/SkyCore/Alerts.swift Tests/SkyCoreTests/AlertTests.swift
git commit -m "feat(skycore): alert state machine and flavoured copy table"
```

---

### Task 11: Config and telescope presets

**Files:**
- Create: `Sources/SkyCore/Config.swift`, `Sources/SkyCore/Resources/presets/telescopes.json`
- Test: `Tests/SkyCoreTests/ConfigTests.swift`

**Interfaces:**
- Produces:
  - `public struct TelescopePreset: Codable, Equatable, Sendable, Identifiable { id, name, widthDeg, heightDeg, source }`
  - `public enum TelescopePresets { static func bundled() throws -> [TelescopePreset] }`
  - `public struct Config: Codable, Equatable, Sendable { sites: [Site], activeSiteName: String?, fov: FieldOfView, fovPresetID: String?, goRule: GoRule, alerts: AlertSettings, flavour: Flavour, loginItem: Bool, notifyEnabled: Bool; static let `default`: Config; var activeSite(resolvedWith auto: Site?) -> Site? }`
  - `public enum ConfigStore { static var defaultURL: URL; static func load(from:) throws -> Config; static func save(_:to:) throws }`

- [ ] **Step 1: Write the presets file**

`Sources/SkyCore/Resources/presets/telescopes.json`:

```json
[
  {"id":"dwarf-mini","name":"DwarfLab DWARF Mini","widthDeg":2.1,"heightDeg":1.2,"source":"telescopicwatch.com review, 150 mm f/5, IMX662"},
  {"id":"dwarf-3","name":"DwarfLab DWARF 3","widthDeg":2.93,"heightDeg":1.65,"source":"skiesandscopes.com"},
  {"id":"seestar-s50","name":"ZWO Seestar S50","widthDeg":1.29,"heightDeg":0.73,"source":"seestar.com FAQ, 250 mm f/5, IMX462"},
  {"id":"dslr-apsc-200","name":"APS-C camera, 200 mm lens","widthDeg":6.7,"heightDeg":4.5,"source":"computed from 23.5 x 15.6 mm sensor"}
]
```

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SkyCore

@Test func presetsLoad() throws {
    let p = try TelescopePresets.bundled()
    #expect(p.count == 4)
    #expect(p.first { $0.id == "dwarf-mini" }?.widthDeg == 2.1)
}

@Test func defaultConfigIsSane() {
    let c = Config.default
    #expect(c.sites.isEmpty && c.activeSiteName == nil)
    #expect(c.fov == FieldOfView(widthDeg: 2.1, heightDeg: 1.2))
    #expect(c.goRule == GoRule())
    #expect(c.flavour == .watch && c.notifyEnabled && !c.loginItem)
}

@Test func roundTripsThroughDisk() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = dir.appendingPathComponent("config.json")
    var c = Config.default
    c.sites = [Site(name: "Home", latitude: 53.38, longitude: -1.47, elevationM: 100, timeZoneID: "Europe/London", bortle: 5)]
    c.activeSiteName = "Home"
    try ConfigStore.save(c, to: url)
    #expect(try ConfigStore.load(from: url) == c)
    #expect(try ConfigStore.load(from: dir.appendingPathComponent("missing.json")) == Config.default)
}

@Test func activeSiteResolution() {
    var c = Config.default
    let home = Site(name: "Home", latitude: 1, longitude: 2, elevationM: 0, timeZoneID: "UTC", bortle: 4)
    let auto = Site(name: "Current location", latitude: 9, longitude: 9, elevationM: 0, timeZoneID: "UTC", bortle: 5)
    c.sites = [home]
    #expect(c.activeSite(auto: auto) == auto)
    #expect(c.activeSite(auto: nil) == home)
    c.activeSiteName = "Home"
    #expect(c.activeSite(auto: auto) == home)
    c.sites = []; c.activeSiteName = nil
    #expect(c.activeSite(auto: nil) == nil)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `scripts/test.sh`
Expected: `cannot find 'Config' in scope`.

- [ ] **Step 4: Implement Config.swift**

```swift
import Foundation

public struct TelescopePreset: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let widthDeg: Double
    public let heightDeg: Double
    public let source: String
    public var fov: FieldOfView { FieldOfView(widthDeg: widthDeg, heightDeg: heightDeg) }
}

public enum TelescopePresets {
    public static func bundled() throws -> [TelescopePreset] {
        guard let url = Bundle.module.url(forResource: "telescopes", withExtension: "json", subdirectory: "Resources/presets") else {
            throw CatalogError.missingResource("telescopes")
        }
        return try JSONDecoder().decode([TelescopePreset].self, from: Data(contentsOf: url))
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var sites: [Site] = []
    public var activeSiteName: String? = nil          // nil = automatic location when available
    public var fov = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
    public var fovPresetID: String? = "dwarf-mini"
    public var goRule = GoRule()
    public var alerts = AlertSettings()
    public var flavour: Flavour = .watch
    public var loginItem = false
    public var notifyEnabled = true

    public init() {}
    public static let `default` = Config()

    /// Manual site wins when named; otherwise the automatic fix; otherwise the first saved site.
    public func activeSite(auto: Site?) -> Site? {
        if let n = activeSiteName, let s = sites.first(where: { $0.name == n }) { return s }
        return auto ?? sites.first
    }
}

public enum ConfigStore {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nightwatch", isDirectory: true).appendingPathComponent("config.json")
    }

    public static func load(from url: URL) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return .default }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(Config.self, from: Data(contentsOf: url))
    }

    public static func save(_ config: Config, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601
        try e.encode(config).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `scripts/test.sh`
Expected: all Config tests pass and the whole suite is green.

- [ ] **Step 6: Commit**

```bash
git add Sources/SkyCore/Config.swift Sources/SkyCore/Resources/presets Tests/SkyCoreTests/ConfigTests.swift
git commit -m "feat(skycore): config store and telescope presets"
```

---
### Task 12: App shell — Store, Scheduler, Location, Notifier, build script

**Files:**
- Create: `Sources/Nightwatch/Store.swift`, `Scheduler.swift`, `LocationProvider.swift`, `Notifier.swift`, `Info.plist`, `Views/Theme.swift`
- Modify: `Sources/Nightwatch/NightwatchApp.swift`
- Create: `scripts/build-app.sh`

**Interfaces:**
- Consumes: everything public in `SkyCore`.
- Produces:
  - `@MainActor final class Store: ObservableObject { @Published config, plan: NightPlan?, tomorrow: NightPlan?, events: [SkyEvent], forecast: Forecast?, alertState: AlertState?, lastError: String?, autoSite: Site?; var copy: Copy; var site: Site?; var iconName: String; func refresh(force: Bool) async; func saveConfig(); static let cacheDir: URL }`
  - `final class Scheduler { init(interval:, onFire: @escaping () -> Void); func start() }`
  - `final class LocationProvider: NSObject { func requestOnce() async -> Site? }`
  - `enum Notifier { static func requestAuthorisation() async; static func post(_ n: AlertNotification) }`
  - `enum Theme { colours and glyph names }`

- [ ] **Step 1: Write Info.plist and build-app.sh**

`Sources/Nightwatch/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Nightwatch</string>
  <key>CFBundleDisplayName</key><string>Nightwatch</string>
  <key>CFBundleExecutable</key><string>Nightwatch</string>
  <key>CFBundleIdentifier</key><string>io.github.rsutcliffe.nightwatch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSLocationUsageDescription</key><string>Nightwatch uses your location to compute sunset, darkness and what is visible from where you are. You can set a site manually instead.</string>
  <key>NSHumanReadableCopyright</key><string>MIT licence. Data attributions in About.</string>
</dict>
</plist>
```

`scripts/build-app.sh`:

```bash
#!/bin/zsh
# Builds Nightwatch.app with SwiftPM only, signs it ad hoc, installs to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Nightwatch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Sources/Nightwatch/Info.plist "$APP/Contents/Info.plist"
cp .build/release/Nightwatch "$APP/Contents/MacOS/Nightwatch"
cp -R .build/release/Nightwatch_SkyCore.bundle "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
if [[ "${1:-}" == "--no-install" ]]; then echo "Built $APP"; exit 0; fi
pkill -x Nightwatch || true
rm -rf /Applications/Nightwatch.app
cp -R "$APP" /Applications/Nightwatch.app
open /Applications/Nightwatch.app
echo "Installed and launched /Applications/Nightwatch.app"
```

Add `build/` to `.gitignore`. `chmod +x scripts/build-app.sh`.

- [ ] **Step 2: Write Theme.swift**

```swift
import SwiftUI

enum Theme {
    static let bg = Color(red: 0.078, green: 0.090, blue: 0.118)          // #14171e
    static let card = Color(red: 0.106, green: 0.122, blue: 0.157)        // #1b1f28
    static let line = Color(red: 0.149, green: 0.165, blue: 0.208)        // #262a35
    static let text = Color(red: 0.910, green: 0.918, blue: 0.941)        // #e8eaf0
    static let dim = Color(red: 0.545, green: 0.576, blue: 0.655)         // #8b93a7
    static let accent = Color(red: 0.431, green: 0.906, blue: 0.718)      // #6ee7b7
    static let warn = Color(red: 0.957, green: 0.722, blue: 0.376)        // #f4b860
    static let bad = Color(red: 0.941, green: 0.549, blue: 0.549)         // #f08c8c

    static func icon(for plan: NightPlan?, stale: Bool, now: Date) -> String {
        if stale { return "star.slash" }
        guard let p = plan, let w = p.primary else { return "star" }
        return now >= w.start.addingTimeInterval(-1800) && now < w.end ? "star.fill" : "star.circle"
    }

    static func glyph(for group: TargetGroup) -> String {
        switch group {
        case .nebulae: "cloud.fill"
        case .galaxies: "hurricane"
        case .clusters: "sparkles"
        case .planets: "circle.circle"
        case .events: "calendar"
        case .constellations: "point.3.connected.trianglepath.dotted"
        }
    }
}
```

- [ ] **Step 3: Write LocationProvider.swift, Notifier.swift, Scheduler.swift**

`LocationProvider.swift`:

```swift
import CoreLocation
import SkyCore

final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Site?, Never>?

    /// One fix, or nil when denied, restricted or timed out. Never prompts more than macOS itself does.
    func requestOnce() async -> Site? {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorized || manager.authorizationStatus == .notDetermined else { return nil }
        return await withCheckedContinuation { c in
            continuation = c
            manager.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.finish(nil) }
        }
    }

    private func finish(_ site: Site?) {
        continuation?.resume(returning: site)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return finish(nil) }
        finish(Site(name: "Current location", latitude: l.coordinate.latitude, longitude: l.coordinate.longitude,
                    elevationM: max(0, l.altitude), timeZoneID: TimeZone.current.identifier, bortle: 5))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(nil) }
}
```

`Notifier.swift`:

```swift
import UserNotifications
import SkyCore

enum Notifier {
    static func requestAuthorisation() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func post(_ n: AlertNotification) {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.sound = n.kind == .go ? .default : nil
        let req = UNNotificationRequest(identifier: "nightwatch-\(n.kind)-\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
```

`Scheduler.swift`:

```swift
import AppKit
import Foundation

/// Fires `onFire` every `interval` seconds while the app runs, plus once on wake from sleep.
final class Scheduler {
    private let activity = NSBackgroundActivityScheduler(identifier: "io.github.rsutcliffe.nightwatch.patrol")
    private let onFire: () -> Void

    init(interval: TimeInterval = 30 * 60, onFire: @escaping () -> Void) {
        self.onFire = onFire
        activity.repeats = true
        activity.interval = interval
        activity.tolerance = interval / 3
        activity.qualityOfService = .utility
    }

    func start() {
        activity.schedule { [onFire] completion in
            DispatchQueue.main.async { onFire() }
            completion(.finished)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [onFire] _ in
            onFire()
        }
    }
}
```

- [ ] **Step 4: Write Store.swift**

```swift
import Foundation
import SkyCore
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var config: Config
    @Published var plan: NightPlan?
    @Published var tomorrow: NightPlan?
    @Published var events: [SkyEvent] = []
    @Published var forecast: Forecast?
    @Published var alertState: AlertState?
    @Published var autoSite: Site?
    @Published var lastError: String?
    @Published var refreshing = false

    static let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Nightwatch", isDirectory: true)
    private let fetcher: Fetcher = URLSessionFetcher()
    private let catalog: Catalog
    private let constellations: [Constellation]
    private let showers: [MeteorShower]
    private var comets: [CometElements] = []
    private var tle: TLE?

    init() {
        config = (try? ConfigStore.load(from: ConfigStore.defaultURL)) ?? .default
        catalog = (try? Catalog.bundled()) ?? Catalog(objects: [])
        constellations = (try? Constellations.bundled()) ?? []
        showers = (try? MeteorShowers.bundled()) ?? []
        try? FileManager.default.createDirectory(at: Store.cacheDir, withIntermediateDirectories: true)
        forecast = Store.read("forecast.json")
        alertState = Store.read("alerts-state.json")
        comets = Store.read("comets.json") ?? []
        tle = Store.read("iss-tle.json")
        if catalog.objects.isEmpty { lastError = "Catalogue missing: run scripts/fetch-data.sh and rebuild." }
    }

    var copy: Copy { Copy(flavour: config.flavour) }
    var site: Site? { config.activeSite(auto: autoSite) }
    var isStale: Bool { (forecast?.fetchedAt).map { Date().timeIntervalSince($0) > 6 * 3600 } ?? true }
    var iconName: String { Theme.icon(for: plan, stale: isStale, now: Date()) }

    func saveConfig() {
        try? ConfigStore.save(config, to: ConfigStore.defaultURL)
        Task { await recompute(now: Date()) }
    }

    /// Fetch when the cache is older than 30 minutes (or forced), then recompute everything.
    func refresh(force: Bool) async {
        guard let site else { lastError = "No site. Add one in Settings or allow location access."; return }
        refreshing = true
        defer { refreshing = false }
        let now = Date()
        if force || (forecast?.fetchedAt).map({ now.timeIntervalSince($0) > 30 * 60 }) ?? true {
            do {
                forecast = try await ForecastService.fetch(site: site, fetcher: fetcher, now: now)
                Store.write(forecast, "forecast.json")
                lastError = nil
            } catch {
                lastError = "Forecast fetch failed: \(error.localizedDescription)"
            }
        }
        await refreshAuxiliary(now: now)
        await recompute(now: now)
    }

    /// Comet elements daily, ISS elements every 2 hours (CelesTrak asks for no more). The MPC file is gzip, so it goes through gunzip.
    private func refreshAuxiliary(now: Date) async {
        if Store.age("comets.json") > 86_400, let data = try? await fetcher.get(Comets.url), let c = try? Comets.decode(Store.gunzip(data)) {
            comets = c; Store.write(c, "comets.json")
        }
        if Store.age("iss-tle.json") > 2 * 3600, let data = try? await fetcher.get(Satellites.issURL),
           let t = try? Satellites.parseTLE(String(decoding: data, as: UTF8.self)) {
            tle = t; Store.write(t, "iss-tle.json")
        }
    }

    /// The night whose sunset is coming up, or the one in progress: local date of (now − 9 h). ponytail: a fixed 9 h
    /// offset means the previous night stays "tonight" until 09:00 local; sunrise-based switching if anyone minds.
    func recompute(now: Date) async {
        guard let site, let fc = forecast else { return }
        let cal = site.calendar
        guard let night = try? Ephemeris.night(localDate: now.addingTimeInterval(-9 * 3600), site: site),
              let next = try? Ephemeris.night(localDate: cal.date(byAdding: .day, value: 1, to: night.localDate)!, site: site) else { return }
        let fov = config.fov, rule = config.goRule
        let p = Planner.plan(night: night, forecast: fc, catalog: catalog, constellations: constellations, site: site, fov: fov, rule: rule)
        let t = Planner.plan(night: next, forecast: fc, catalog: catalog, constellations: constellations, site: site, fov: fov, rule: rule)
        plan = p; tomorrow = t
        events = buildEvents(night: night, site: site, now: now)
        Store.write(p, "plan.json")
        if config.notifyEnabled {
            let r = AlertEngine.step(now: now, tonight: p, tomorrow: t, state: alertState, settings: config.alerts,
                                     forecastFetchedAt: fc.fetchedAt, site: site, copy: copy)
            alertState = r.state
            Store.write(r.state, "alerts-state.json")
            if let n = r.notification { Notifier.post(n) }
        }
    }

    private func buildEvents(night: Night, site: Site, now: Date) -> [SkyEvent] {
        var ev = Events.showers(night: night, site: site, showers: showers)
        ev += Events.eclipses(after: now, site: site, withinDays: 60)
        let mid = night.darkStart.map { $0.addingTimeInterval((night.darkEnd ?? $0).timeIntervalSince($0) / 2) } ?? night.sunset
        ev += Events.conjunctions(at: mid, site: site, maxSeparationDeg: 3)
        for (c, pos) in Comets.bright(comets, at: mid, limit: 12) {
            let alt = Ephemeris.altAz(raHours: pos.raHours, decDeg: pos.decDeg, at: mid, site: site).alt
            guard alt > 20 else { continue }
            ev.append(SkyEvent(id: "comet-\(c.designation)", kind: .comet, title: c.designation,
                               detail: String(format: "mag %.1f · alt %.0f°", pos.magnitude, alt), time: mid, endTime: nil, raHours: pos.raHours, decDeg: pos.decDeg))
        }
        if let tle, let passes = try? Satellites.visiblePasses(tle: tle, site: site, from: night.sunset, to: night.sunrise, minPeakElevation: 30) {
            for p in passes {
                ev.append(SkyEvent(id: "iss-\(Int(p.rise.timeIntervalSince1970))", kind: .issPass, title: "ISS pass",
                                   detail: String(format: "max %.0f° at %@", p.maxElevationDeg, Copy.hhmm(p.peak, site: site)),
                                   time: p.rise, endTime: p.set, raHours: nil, decDeg: nil))
            }
        }
        return ev.sorted { $0.time < $1.time }
    }

    // MARK: cache helpers
    static func url(_ name: String) -> URL { cacheDir.appendingPathComponent(name) }
    static func age(_ name: String) -> TimeInterval {
        guard let d = try? FileManager.default.attributesOfItem(atPath: url(name).path)[.modificationDate] as? Date else { return .infinity }
        return Date().timeIntervalSince(d)
    }
    static func read<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(T.self, from: data)
    }
    static func write<T: Encodable>(_ value: T?, _ name: String) {
        guard let value else { return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(value).write(to: url(name), options: .atomic)
    }
    /// gzip via Foundation is unavailable; shell out to the system gunzip for the MPC file.
    static func gunzip(_ data: Data) -> Data {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cometels.json.gz")
        try? data.write(to: tmp)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip"); p.arguments = ["-c", tmp.path]
        let pipe = Pipe(); p.standardOutput = pipe
        try? p.run(); let out = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return out
    }
}
```

- [ ] **Step 5: Write NightwatchApp.swift**

```swift
import SwiftUI
import SkyCore

@main
struct NightwatchApp: App {
    @StateObject private var store = Store()
    @State private var scheduler: Scheduler?
    private let location = LocationProvider()

    var body: some Scene {
        MenuBarExtra {
            TonightView()
                .environmentObject(store)
                .frame(width: 360)
                .task { await boot() }
        } label: {
            Image(systemName: store.iconName)
        }
        .menuBarExtraStyle(.window)

        Window("Targets", id: "targets") { TargetsView().environmentObject(store) }
            .defaultSize(width: 980, height: 640)
        Window("Settings", id: "settings") { SettingsView().environmentObject(store) }
            .defaultSize(width: 520, height: 560)
        Window("About Nightwatch", id: "about") { AboutView() }
            .defaultSize(width: 420, height: 420)
    }

    @MainActor
    private func boot() async {
        guard scheduler == nil else { return }
        await Notifier.requestAuthorisation()
        if store.config.activeSiteName == nil { store.autoSite = await location.requestOnce() }
        await store.refresh(force: false)
        let s = Scheduler { Task { await store.refresh(force: false) } }
        s.start()
        scheduler = s
    }
}
```

Until Task 13 adds the views, create stubs so it compiles:

```swift
// Views/TonightView.swift, Views/TargetsView.swift, Views/SettingsView.swift, Views/AboutView.swift (temporary)
import SwiftUI
struct TonightView: View { var body: some View { Text("Tonight").padding() } }
struct TargetsView: View { var body: some View { Text("Targets") } }
struct SettingsView: View { var body: some View { Text("Settings") } }
struct AboutView: View { var body: some View { Text("About") } }
```

- [ ] **Step 6: Build, bundle and smoke-test**

```bash
scripts/build-app.sh --no-install
ls build/Nightwatch.app/Contents/Resources/     # must show Nightwatch_SkyCore.bundle
open build/Nightwatch.app && sleep 4 && pgrep -x Nightwatch && echo RUNNING
ls ~/Library/Caches/Nightwatch/                 # forecast.json appears after first refresh (needs network and a site)
pkill -x Nightwatch
```

Expected: the process runs, a star icon appears in the menu bar, no Dock icon. `forecast.json` appears only once a site exists: for this smoke test create `~/Library/Application Support/Nightwatch/config.json` with one site first:

```bash
mkdir -p ~/Library/Application\ Support/Nightwatch && cat > ~/Library/Application\ Support/Nightwatch/config.json <<'EOF'
{"sites":[{"name":"Home","latitude":53.38,"longitude":-1.47,"elevationM":100,"timeZoneID":"Europe/London","bortle":5}],"activeSiteName":"Home","fov":{"widthDeg":2.1,"heightDeg":1.2},"fovPresetID":"dwarf-mini","goRule":{"minHours":3,"maxCloudPct":25,"minAltitudeDeg":30},"alerts":{"headsUp":true,"tomorrowPreview":true,"preWindowMinutes":30,"cancelOnDowngrade":true,"quietStartHour":0,"quietEndHour":7},"flavour":"watch","loginItem":false,"notifyEnabled":true}
EOF
```

Replace the coordinates with the owner's real site before handing over; the values above are the test site.

- [ ] **Step 7: Commit**

```bash
git add scripts/build-app.sh Sources/Nightwatch .gitignore
git commit -m "feat(app): menu bar shell with store, scheduler, location and notifications"
```

---

### Task 13: Tonight popover

**Files:**
- Replace: `Sources/Nightwatch/Views/TonightView.swift`

**Interfaces:**
- Consumes: `Store` (`plan`, `forecast`, `copy`, `site`, `isStale`, `refresh`, `config.notifyEnabled`, `saveConfig`), `Theme`, `Copy.hhmm`.
- Produces: `TonightView` opening the Targets and Settings windows via `openWindow(id:)`.

- [ ] **Step 1: Write TonightView.swift**

```swift
import SwiftUI
import SkyCore

struct TonightView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let plan = store.plan, let site = store.site {
                verdict(plan, site)
                cloudStrip(plan)
                tiles(plan, site)
                best(plan)
            } else {
                Text(store.lastError ?? "Waiting for the first forecast…").font(.callout).foregroundStyle(Theme.dim).padding(.vertical, 20)
            }
            footer
        }
        .padding(16)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TONIGHT · \(store.site?.name.uppercased() ?? "NO SITE")").font(.caption).foregroundStyle(Theme.dim)
                if let s = store.site, let p = store.plan {
                    Text("\(p.night.key) · Bortle \(s.bortle)").font(.caption).foregroundStyle(Theme.dim)
                }
            }
            Spacer()
            Button { openWindow(id: "settings") } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).foregroundStyle(Theme.dim)
        }
    }

    private func verdict(_ plan: NightPlan, _ site: Site) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 7)
                Circle().trim(from: 0, to: Double(plan.score) / 100).stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(plan.score)").font(.system(size: 24, weight: .semibold))
            }.frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                if let w = plan.primary {
                    Text("Clear window tonight").font(.title3.weight(.semibold))
                    Text("\(Copy.hhmm(w.start, site: site)) → \(Copy.hhmm(w.end, site: site)) · \(String(format: "%.1f h", w.hours))").foregroundStyle(Theme.text)
                    Text("Notify at \(Copy.hhmm(w.start.addingTimeInterval(-Double(store.config.alerts.preWindowMinutes) * 60), site: site))").font(.caption).foregroundStyle(Theme.dim)
                } else if !plan.night.hasDarkness {
                    Text("No astronomical darkness").font(.title3.weight(.semibold))
                    Text("Too far north or south for this date.").font(.caption).foregroundStyle(Theme.dim)
                } else {
                    Text(store.copy.noWindow).font(.title3.weight(.semibold))
                    if let t = store.tomorrow, let w = t.primary {
                        Text("Tomorrow: \(Copy.hhmm(w.start, site: site)) → \(Copy.hhmm(w.end, site: site))").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }

    private func cloudStrip(_ plan: NightPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(plan.darkHours, id: \.time) { h in
                    let clear = h.cloudTotal <= store.config.goRule.maxCloudPct
                    RoundedRectangle(cornerRadius: 2)
                        .fill(clear ? Theme.accent : Theme.line)
                        .frame(height: max(3, CGFloat(h.cloudTotal) * 0.4))
                        .frame(maxWidth: .infinity)
                }
            }.frame(height: 44, alignment: .bottom)
            HStack {
                if let f = plan.darkHours.first, let l = plan.darkHours.last, let s = store.site {
                    Text(Copy.hhmm(f.time, site: s)); Spacer(); Text(Copy.hhmm(l.time, site: s))
                }
            }.font(.caption2).foregroundStyle(Theme.dim)
            Text("Cloud cover during darkness · bar height = % cloud · Open-Meteo").font(.caption2).foregroundStyle(Theme.dim)
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
            Text(value).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tiles(_ plan: NightPlan, _ site: Site) -> some View {
        let dark = plan.night.darkStart.map { "\(Copy.hhmm($0, site: site))–\(Copy.hhmm(plan.night.darkEnd!, site: site))" } ?? "none"
        let moon = "\(Int((plan.moonIllumination * 100).rounded()))%" + (plan.moonSet.map { " · sets \(Copy.hhmm($0, site: site))" } ?? "")
        let seeing = plan.darkHours.compactMap(\.seeing)
        let seeingText = seeing.isEmpty ? "n/a" : ["", "<0.5″", "0.5–0.75″", "0.75–1″", "1–1.25″", "1.25–1.5″", "1.5–2″", "2–2.5″", ">2.5″"][min(8, seeing.reduce(0, +) / seeing.count)]
        let wind = plan.darkHours.compactMap(\.windKmh)
        let windText = wind.isEmpty ? "n/a" : String(format: "%.0f km/h", wind.reduce(0, +) / Double(wind.count))
        let spread = plan.darkHours.compactMap { h -> Double? in guard let t = h.tempC, let d = h.dewPointC else { return nil }; return t - d }.min()
        let dewText = spread.map { $0 < 2 ? "High" : ($0 < 4 ? "Medium" : "Low") } ?? "n/a"
        let frost = plan.darkHours.compactMap(\.tempC).min().map { $0 <= 0 } ?? false
        let transp = plan.darkHours.compactMap(\.transparency)
        let transpText = transp.isEmpty ? "n/a" : (transp.reduce(0, +) / transp.count <= 3 ? "Good" : "Average")
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            tile("Dark", dark); tile("Moon", moon); tile("Seeing", seeingText)
            tile("Wind", windText); tile(frost ? "Frost likely" : "Dew risk", dewText); tile("Transparency", transpText)
        }
    }

    private func best(_ plan: NightPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BEST TONIGHT").font(.caption).foregroundStyle(Theme.dim)
                Spacer()
                Button("All targets →") { openWindow(id: "targets") }.buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent)
            }
            HStack(spacing: 8) {
                ForEach(plan.best) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        ThumbnailView(target: t).frame(height: 64)
                        Text(t.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(t.group.displayName).font(.caption2).foregroundStyle(Theme.dim)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle(isOn: Binding(get: { store.config.notifyEnabled }, set: { store.config.notifyEnabled = $0; store.saveConfig() })) {
                Text("Notify when clear").font(.callout)
            }.toggleStyle(.checkbox)
            Spacer()
            if store.refreshing { ProgressView().controlSize(.small) }
            else if let f = store.forecast, let s = store.site {
                Text(store.isStale ? store.copy.offlineSince(Copy.hhmm(f.fetchedAt, site: s)) : "Updated \(Copy.hhmm(f.fetchedAt, site: s))")
                    .font(.caption).foregroundStyle(store.isStale ? Theme.warn : Theme.dim)
            }
            Button(store.copy.refresh) { Task { await store.refresh(force: true) } }.font(.caption)
        }.padding(.top, 4)
    }
}
```

`ThumbnailView` arrives in Task 14; until then add a stub in `Views/TargetsView.swift`:

```swift
struct ThumbnailView: View {
    let target: RankedTarget
    var body: some View { RoundedRectangle(cornerRadius: 8).fill(Theme.card).overlay(Image(systemName: Theme.glyph(for: target.group)).foregroundStyle(Theme.dim)) }
}
```

- [ ] **Step 2: Build and look**

```bash
scripts/build-app.sh
```

Expected: menu bar star; clicking it shows the popover with score ring, window, cloud strip, six tiles, best three targets, footer with the toggle and the flavoured refresh button. Take a screenshot for the PR.

- [ ] **Step 3: Commit**

```bash
git add Sources/Nightwatch/Views
git commit -m "feat(app): tonight popover"
```

---
### Task 14: Thumbnails, target browser and detail

**Files:**
- Create: `Sources/Nightwatch/Thumbnails.swift`, `Sources/Nightwatch/Views/DetailView.swift`
- Replace: `Sources/Nightwatch/Views/TargetsView.swift` (remove the stub `ThumbnailView` from Task 13)

**Interfaces:**
- Consumes: `Store.plan.targets`, `Store.events`, `Store.config.fov`, `RankedTarget`, `SkyEvent`, `Constellation`.
- Produces: `enum Thumbnails { static func url(for:fov:) -> URL; static func image(for:fov:) async -> NSImage? }`, `struct ThumbnailView: View`, `struct TargetsView: View`, `struct DetailView: View`.

- [ ] **Step 1: Write Thumbnails.swift**

```swift
import AppKit
import SkyCore

/// DSS2 colour cutouts from CDS hips2fits at the user's field of view (or 1.5 × the object when it is bigger), cached forever per object and FOV.
enum Thumbnails {
    static let dir = Store.cacheDir.appendingPathComponent("thumbs", isDirectory: true)

    static func fovDeg(for t: RankedTarget, fov: FieldOfView) -> Double {
        let objectDeg = (t.sizeArcmin ?? 0) / 60
        return max(fov.widthDeg, objectDeg * 1.5)
    }

    static func url(for t: RankedTarget, fov: FieldOfView) -> URL {
        var c = URLComponents(string: "https://alasky.cds.unistra.fr/hips-image-services/hips2fits")!
        let f = fovDeg(for: t, fov: fov)
        c.queryItems = [
            .init(name: "hips", value: "CDS/P/DSS2/color"),
            .init(name: "ra", value: String(format: "%.5f", t.raHours * 15)),
            .init(name: "dec", value: String(format: "%.5f", t.decDeg)),
            .init(name: "fov", value: String(format: "%.3f", f)),
            .init(name: "width", value: "480"),
            .init(name: "height", value: String(Int(480 * fov.heightDeg / fov.widthDeg))),
            .init(name: "projection", value: "TAN"),
            .init(name: "format", value: "jpg")
        ]
        return c.url!
    }

    static func file(for t: RankedTarget, fov: FieldOfView) -> URL {
        dir.appendingPathComponent("\(t.id)-\(String(format: "%.2fx%.2f", fov.widthDeg, fov.heightDeg)).jpg")
    }

    static func image(for t: RankedTarget, fov: FieldOfView) async -> NSImage? {
        guard t.group != .constellations, t.group != .planets else { return nil }
        let f = file(for: t, fov: fov)
        if let img = NSImage(contentsOf: f) { return img }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? await URLSessionFetcher().get(url(for: t, fov: fov)), let img = NSImage(data: data) else { return nil }
        try? data.write(to: f, options: .atomic)
        return img
    }
}

struct ThumbnailView: View {
    @EnvironmentObject var store: Store
    let target: RankedTarget
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.055, green: 0.063, blue: 0.094))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clipShape(RoundedRectangle(cornerRadius: 8))
            } else if target.group == .constellations, let c = store.constellation(target.id) {
                ConstellationFigure(constellation: c).padding(6)
            } else {
                Image(systemName: Theme.glyph(for: target.group)).font(.title2).foregroundStyle(Theme.dim)
            }
        }
        .task(id: target.id) { image = await Thumbnails.image(for: target, fov: store.config.fov) }
    }
}

/// Stick figure drawn from the d3-celestial polylines, normalised into the view.
struct ConstellationFigure: View {
    let constellation: Constellation
    var body: some View {
        GeometryReader { g in
            let pts = constellation.lines.flatMap { $0 }
            let ras = pts.map { $0[0] }, decs = pts.map { $0[1] }
            if let minRA = ras.min(), let maxRA = ras.max(), let minDec = decs.min(), let maxDec = decs.max(), maxRA > minRA, maxDec > minDec {
                Path { p in
                    for line in constellation.lines {
                        for (i, pt) in line.enumerated() {
                            let x = g.size.width * (1 - (pt[0] - minRA) / (maxRA - minRA))   // RA increases to the left
                            let y = g.size.height * (1 - (pt[1] - minDec) / (maxDec - minDec))
                            i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }.stroke(Theme.accent.opacity(0.8), lineWidth: 1)
            }
        }
    }
}
```

Add to `Store`:

```swift
    func constellation(_ id: String) -> Constellation? { constellations.first { $0.id == id } }
```

- [ ] **Step 2: Write TargetsView.swift**

```swift
import SwiftUI
import SkyCore

struct TargetsView: View {
    @EnvironmentObject var store: Store
    @State private var group: TargetGroup = .nebulae
    @State private var fitsOnly = false
    @State private var includeMoonWashed = false
    @State private var search = ""
    @State private var selected: RankedTarget?

    private var targets: [RankedTarget] { store.plan?.targets ?? [] }

    private func count(_ g: TargetGroup) -> Int {
        g == .events ? store.events.count : targets.filter { $0.group == g }.count
    }

    private var visible: [RankedTarget] {
        targets.filter { $0.group == group }
            .filter { !fitsOnly || $0.fit == .fits }
            .filter { includeMoonWashed || !$0.moonWashed }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(TargetGroup.allCases, id: \.self, selection: $group) { g in
                Label { HStack { Text(g.displayName); Spacer(); Text("\(count(g))").foregroundStyle(Theme.dim) } } icon: { Image(systemName: Theme.glyph(for: g)) }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Fits my field of view", isOn: $fitsOnly)
                    Toggle("Include Moon-washed", isOn: $includeMoonWashed)
                }.font(.caption).padding(10)
            }
            .navigationSplitViewColumnWidth(232)
        } detail: {
            if let selected {
                DetailView(target: selected) { self.selected = nil }
            } else if group == .events {
                eventsList
            } else {
                grid
            }
        }
        .searchable(text: $search, prompt: "M42, Orion, comet…")
        .preferredColorScheme(.dark)
        .background(Theme.bg)
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.displayName).font(.title2.weight(.semibold))
                if let w = store.plan?.primary, let s = store.site {
                    Text("Sorted by fit and altitude during tonight's clear window · \(Copy.hhmm(w.start, site: s))–\(Copy.hhmm(w.end, site: s))").font(.caption).foregroundStyle(Theme.dim)
                } else {
                    Text(store.copy.noWindow).font(.caption).foregroundStyle(Theme.dim)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top], 20)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(visible) { t in
                    Button { selected = t } label: { card(t) }.buttonStyle(.plain)
                }
            }.padding(20)
        }
    }

    private func badge(_ t: RankedTarget) -> some View {
        let (text, colour): (String, Color) = t.moonWashed ? ("Moon-washed", Theme.bad) : (t.fit == .fits ? ("Fits frame", Theme.accent) : (t.fit == .small ? ("Small", Theme.warn) : ("Mosaic", Theme.warn)))
        return Text(text).font(.caption2).padding(.horizontal, 7).padding(.vertical, 3).background(colour.opacity(0.15)).foregroundStyle(colour).clipShape(Capsule())
    }

    private func card(_ t: RankedTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ThumbnailView(target: t).frame(height: 110).overlay(alignment: .topTrailing) { badge(t).padding(8) }
            HStack(alignment: .firstTextBaseline) {
                Text(t.name).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                if let m = t.magnitude { Text(String(format: "mag %.1f", m)).font(.caption2).foregroundStyle(Theme.dim) }
            }
            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line).frame(height: 4)
                        Capsule().fill(t.moonWashed ? Theme.dim : Theme.accent).frame(width: g.size.width * t.visibleFraction, height: 4)
                    }
                }.frame(height: 4)
                if let s = store.site { Text("best \(Copy.hhmm(t.peakTime, site: s)) · \(Int(t.peakAltDeg))°").font(.caption2).foregroundStyle(Theme.text) }
            }
        }
        .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }

    private var eventsList: some View {
        List(store.events) { e in
            HStack {
                Image(systemName: e.kind == .issPass ? "airplane" : (e.kind == .meteorShower ? "sparkle" : (e.kind == .comet ? "comet" : "moon.stars"))).foregroundStyle(Theme.accent)
                VStack(alignment: .leading) {
                    Text(e.title).font(.callout.weight(.semibold))
                    Text(e.detail).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                if let s = store.site { Text(e.kind == .lunarEclipse || e.kind == .solarEclipse ? e.time.formatted(date: .abbreviated, time: .shortened) : Copy.hhmm(e.time, site: s)).font(.caption).foregroundStyle(Theme.dim) }
            }.padding(.vertical, 4)
        }
        .overlay { if store.events.isEmpty { Text("No events tonight").foregroundStyle(Theme.dim) } }
    }
}
```

- [ ] **Step 3: Write DetailView.swift**

```swift
import SwiftUI
import SkyCore

struct DetailView: View {
    @EnvironmentObject var store: Store
    let target: RankedTarget
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Button(action: onBack) { Image(systemName: "chevron.left") }; Text(target.group.displayName).font(.caption).foregroundStyle(Theme.dim) }
                ZStack {
                    ThumbnailView(target: target).frame(height: 260)
                    if target.group != .constellations {
                        let fovDeg = Thumbnails.fovDeg(for: target, fov: store.config.fov)
                        let w = 360 * store.config.fov.widthDeg / fovDeg
                        RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: w, height: w * store.config.fov.heightDeg / store.config.fov.widthDeg)
                    }
                }
                Text("dashed = your field of view").font(.caption2).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
                Text(target.name).font(.title2.weight(.semibold))
                Text(target.subtitle + (target.sizeArcmin.map { String(format: " · %.0f′", $0) } ?? "") + (target.magnitude.map { String(format: " · mag %.1f", $0) } ?? "")).foregroundStyle(Theme.dim)
                if let s = store.site, let w = store.plan?.primary {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        tile("Best", "\(Copy.hhmm(target.peakTime, site: s)) · \(Int(target.peakAltDeg))°")
                        tile("Above \(Int(store.config.goRule.minAltitudeDeg))°", "\(Int(target.visibleFraction * 100))% of window")
                        tile("Moon sep.", "\(Int(target.moonSepDeg))°")
                        tile("Suggested", String(format: "%.0f min stack", min(w.hours, 3) * 60))
                    }
                    altitudeCurve(site: s, window: w)
                }
                Text(String(format: "RA %.2fh · Dec %+.1f°", target.raHours, target.decDeg)).font(.caption).foregroundStyle(Theme.dim)
            }.padding(16)
        }
        .background(Theme.bg).foregroundStyle(Theme.text)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(label).font(.caption2).foregroundStyle(Theme.dim); Text(value).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7) }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Altitude from sunset to sunrise, clear window shaded, 30° floor drawn.
    private func altitudeCurve(site: Site, window: ClearWindow) -> some View {
        let night = store.plan!.night
        let span = night.sunrise.timeIntervalSince(night.sunset)
        let samples: [(Double, Double)] = stride(from: 0.0, through: 1.0, by: 1.0 / 48).map { f in
            let t = night.sunset.addingTimeInterval(f * span)
            return (f, Ephemeris.altAz(raHours: target.raHours, decDeg: target.decDeg, at: t, site: site).alt)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("ALTITUDE TONIGHT").font(.caption).foregroundStyle(Theme.dim)
            GeometryReader { g in
                let x = { (f: Double) in g.size.width * f }
                let y = { (alt: Double) in g.size.height * (1 - max(0, min(90, alt)) / 90) }
                Rectangle().fill(Theme.accent.opacity(0.08))
                    .frame(width: x(window.end.timeIntervalSince(night.sunset) / span) - x(window.start.timeIntervalSince(night.sunset) / span))
                    .offset(x: x(window.start.timeIntervalSince(night.sunset) / span))
                Path { p in p.move(to: CGPoint(x: 0, y: y(store.config.goRule.minAltitudeDeg))); p.addLine(to: CGPoint(x: g.size.width, y: y(store.config.goRule.minAltitudeDeg))) }.stroke(Theme.line)
                Path { p in
                    for (i, s) in samples.enumerated() { i == 0 ? p.move(to: CGPoint(x: x(s.0), y: y(s.1))) : p.addLine(to: CGPoint(x: x(s.0), y: y(s.1))) }
                }.stroke(Theme.accent, lineWidth: 2)
            }.frame(height: 70)
            HStack { Text(Copy.hhmm(night.sunset, site: site)); Spacer(); Text(Copy.hhmm(night.sunrise, site: site)) }.font(.caption2).foregroundStyle(Theme.dim)
        }
    }
}
```

- [ ] **Step 4: Build and check**

```bash
scripts/build-app.sh
```

Expected: "All targets" opens the browser; group counts match the popover; nebula cards load DSS thumbnails within a few seconds and `~/Library/Caches/Nightwatch/thumbs/` fills; Constellations group shows stick figures; Events group lists showers, ISS passes and conjunctions; clicking a card opens the detail with the dashed FOV box and altitude curve.

- [ ] **Step 5: Commit**

```bash
git add Sources/Nightwatch
git commit -m "feat(app): target browser with DSS thumbnails, events list and detail view"
```

---

### Task 15: Settings, About, login item

**Files:**
- Replace: `Sources/Nightwatch/Views/SettingsView.swift`, `Sources/Nightwatch/Views/AboutView.swift`

**Interfaces:**
- Consumes: `Store.config`, `Store.saveConfig()`, `TelescopePresets.bundled()`, `SMAppService.mainApp` (`register()`/`unregister()` throw, `status` in `.notRegistered/.enabled/.requiresApproval/.notFound`).

- [ ] **Step 1: Write SettingsView.swift**

```swift
import SwiftUI
import ServiceManagement
import SkyCore

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var presets: [TelescopePreset] = (try? TelescopePresets.bundled()) ?? []
    @State private var newSite = Site(name: "", latitude: 0, longitude: 0, elevationM: 0, timeZoneID: TimeZone.current.identifier, bortle: 5)
    @State private var loginStatus = ""

    var body: some View {
        Form {
            Section(store.copy.siteNoun + "s") {
                Picker("Active", selection: Binding(get: { store.config.activeSiteName ?? "" }, set: { store.config.activeSiteName = $0.isEmpty ? nil : $0; store.saveConfig() })) {
                    Text("Automatic (location)").tag("")
                    ForEach(store.config.sites, id: \.name) { Text($0.name).tag($0.name) }
                }
                ForEach(store.config.sites, id: \.name) { s in
                    HStack { Text(s.name); Spacer(); Text(String(format: "%.3f, %.3f · Bortle %d", s.latitude, s.longitude, s.bortle)).foregroundStyle(Theme.dim).font(.caption) }
                }
                .onDelete { store.config.sites.remove(atOffsets: $0); store.saveConfig() }
                HStack {
                    TextField("Name", text: $newSite.name)
                    TextField("Lat", value: $newSite.latitude, format: .number).frame(width: 70)
                    TextField("Lon", value: $newSite.longitude, format: .number).frame(width: 70)
                    Stepper("Bortle \(newSite.bortle)", value: $newSite.bortle, in: 1...9).frame(width: 110)
                    Button("Add") { store.config.sites.append(newSite); store.saveConfig(); newSite.name = "" }.disabled(newSite.name.isEmpty)
                }
            }
            Section("Field of view") {
                Picker("Preset", selection: Binding(get: { store.config.fovPresetID ?? "custom" }, set: { id in
                    store.config.fovPresetID = id == "custom" ? nil : id
                    if let p = presets.first(where: { $0.id == id }) { store.config.fov = p.fov }
                    store.saveConfig()
                })) {
                    ForEach(presets) { Text($0.name).tag($0.id) }
                    Text("Custom").tag("custom")
                }
                HStack {
                    TextField("Width °", value: Binding(get: { store.config.fov.widthDeg }, set: { store.config.fov.widthDeg = $0; store.config.fovPresetID = nil; store.saveConfig() }), format: .number)
                    TextField("Height °", value: Binding(get: { store.config.fov.heightDeg }, set: { store.config.fov.heightDeg = $0; store.config.fovPresetID = nil; store.saveConfig() }), format: .number)
                }
            }
            Section("Go rule") {
                Stepper("At least \(String(format: "%.0f", store.config.goRule.minHours)) h clear", value: Binding(get: { store.config.goRule.minHours }, set: { store.config.goRule.minHours = $0; store.saveConfig() }), in: 1...8)
                Stepper("Cloud at most \(store.config.goRule.maxCloudPct)%", value: Binding(get: { store.config.goRule.maxCloudPct }, set: { store.config.goRule.maxCloudPct = $0; store.saveConfig() }), in: 5...60, step: 5)
                Stepper("Targets above \(Int(store.config.goRule.minAltitudeDeg))°", value: Binding(get: { store.config.goRule.minAltitudeDeg }, set: { store.config.goRule.minAltitudeDeg = $0; store.saveConfig() }), in: 10...60, step: 5)
            }
            Section("Alerts") {
                Toggle("Evening heads-up (one hour before sunset)", isOn: bind(\.alerts.headsUp))
                Toggle("Tomorrow preview when tonight is out", isOn: bind(\.alerts.tomorrowPreview))
                Stepper("Nudge \(store.config.alerts.preWindowMinutes) min before the window", value: bind(\.alerts.preWindowMinutes), in: 0...120, step: 15)
                Toggle("Cancel notice if the forecast turns", isOn: bind(\.alerts.cancelOnDowngrade))
                HStack {
                    Stepper("Quiet from \(store.config.alerts.quietStartHour):00", value: bind(\.alerts.quietStartHour), in: 0...23)
                    Stepper("to \(store.config.alerts.quietEndHour):00", value: bind(\.alerts.quietEndHour), in: 0...23)
                }
            }
            Section("App") {
                Picker("Wording", selection: bind(\.flavour)) { Text("Nightwatch").tag(Flavour.watch); Text("Plain").tag(Flavour.plain) }
                Toggle("Start at login", isOn: Binding(get: { store.config.loginItem }, set: { on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; store.config.loginItem = on; store.saveConfig() }
                    catch { loginStatus = error.localizedDescription }
                    if SMAppService.mainApp.status == .requiresApproval { loginStatus = "Approve Nightwatch under System Settings › General › Login Items." }
                }))
                if !loginStatus.isEmpty { Text(loginStatus).font(.caption).foregroundStyle(Theme.warn) }
                LabeledContent("Config file") { Text(ConfigStore.defaultURL.path).font(.caption).textSelection(.enabled) }
                Text("Symlink that file into iCloud Drive or any synced folder to share settings across Macs.").font(.caption).foregroundStyle(Theme.dim)
            }
        }
        .formStyle(.grouped)
        .preferredColorScheme(.dark)
    }

    private func bind<T>(_ path: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { store.config[keyPath: path] }, set: { store.config[keyPath: path] = $0; store.saveConfig() })
    }
}
```

- [ ] **Step 2: Write AboutView.swift**

```swift
import SwiftUI

struct AboutView: View {
    private let notice = (try? String(contentsOfFile: Bundle.main.path(forResource: "NOTICE", ofType: nil) ?? "", encoding: .utf8)) ?? ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "star").font(.system(size: 36)).foregroundStyle(Theme.accent)
            Text("Nightwatch").font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · MIT licence").font(.caption).foregroundStyle(Theme.dim)
            ScrollView { Text(notice.isEmpty ? "See NOTICE in the repository for data attributions." : notice).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Weather data by Open-Meteo.com. DSS images copyright AAO, SERC, Caltech and AURA via CDS hips2fits.").font(.caption2).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            TurtleGlyph().frame(width: 28, height: 18).foregroundStyle(Theme.dim.opacity(0.6))
        }
        .padding(20).frame(width: 420).background(Theme.bg).foregroundStyle(Theme.text).preferredColorScheme(.dark)
    }
}

/// Small original turtle silhouette. Unlabelled, decorative.
struct TurtleGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var shell = Path(); shell.addEllipse(in: CGRect(x: w * 0.2, y: h * 0.1, width: w * 0.6, height: h * 0.7))
            var head = Path(); head.addEllipse(in: CGRect(x: w * 0.78, y: h * 0.35, width: w * 0.2, height: h * 0.3))
            var legs = Path()
            for x in [0.25, 0.65] { legs.addEllipse(in: CGRect(x: w * x, y: h * 0.7, width: w * 0.12, height: h * 0.28)) }
            ctx.fill(shell, with: .foreground); ctx.fill(head, with: .foreground); ctx.fill(legs, with: .foreground)
        }
    }
}
```

Add to `scripts/build-app.sh` after the bundle copy: `cp NOTICE "$APP/Contents/Resources/NOTICE"`.

- [ ] **Step 3: Build and check**

```bash
scripts/build-app.sh
```

Expected: Settings opens from the gear; adding a site and changing the preset updates the popover on close; "Start at login" registers (status enabled, or the approval hint appears); About shows the NOTICE text and a small turtle beneath it. Plain wording swaps the refresh button label to "Refresh".

- [ ] **Step 4: Commit**

```bash
git add Sources/Nightwatch scripts/build-app.sh
git commit -m "feat(app): settings, about and login item"
```

---

### Task 16: README, final verification, tag

**Files:**
- Modify: `README.md`
- Create: `docs/uat.md`

- [ ] **Step 1: Finish README.md**

Append to the README from Task 1:

```markdown
## What it does

- Every 30 minutes it fetches Open-Meteo (cloud, dew point, wind, visibility) and 7Timer (seeing, transparency) for your site.
- It computes astronomical darkness, Moon, planets and target visibility locally with Astronomy Engine. Nothing leaves your Mac except those two forecast requests, thumbnail fetches from CDS, and comet/ISS element downloads.
- A night qualifies when there is a contiguous run of at least 3 hours inside astronomical darkness with total cloud at or under 25 % (all adjustable).
- Alerts: a heads-up one hour before local sunset, a nudge 30 minutes before the window opens, and a stand-down if the forecast turns. Quiet hours default to 00:00–07:00. Nothing fires from a forecast older than six hours.
- The target browser groups what is up during the window into nebulae, galaxies, star clusters, planets and Moon, events (meteor showers, eclipses, conjunctions, comets, ISS passes) and constellations, with DSS2 thumbnails and a fits-frame badge relative to your field of view.

## Telescope

Any. Pick a preset (DWARF Mini, DWARF 3, Seestar S50, APS-C at 200 mm) or type your field of view in degrees.

## Settings sync

Settings live in `~/Library/Application Support/Nightwatch/config.json`. Symlink it into iCloud Drive or any synced folder to share across Macs.

## Data sources and licences

See `NOTICE`. Weather data by Open-Meteo.com (CC BY 4.0). 7Timer data is for non-commercial use. OpenNGC is CC BY-SA 4.0. DSS images are copyright AAO, SERC, Caltech and AURA, served by CDS hips2fits.

## Release names

Tags follow the City Watch novels: 0.1 Guards! Guards!, 0.2 Men at Arms, 0.3 Feet of Clay, 0.4 Jingo, 0.5 The Fifth Elephant, 1.0 Night Watch.
```

- [ ] **Step 2: Write docs/uat.md**

```markdown
# Nightwatch UAT

Run on each Mac after `scripts/build-app.sh`.

1. Menu bar shows a star; no Dock icon. → pass when both true.
2. Click the star: popover shows site, score ring, window or "Nothing to see here", cloud strip, six tiles, best three targets, updated time. → pass when all visible within one second.
3. Settings › add your real site, choose it as Active, pick your telescope preset. Close. Popover updates. → pass when the site name changes in the header.
4. Targets window: Nebulae group shows cards with DSS thumbnails; `ls ~/Library/Caches/Nightwatch/thumbs` grows. → pass when at least three jpgs exist.
5. Events group lists at least one item (a meteor shower is active most of the year). → pass.
6. Notifications: System Settings › Notifications shows Nightwatch allowed. Force a go alert by setting Go rule "Cloud at most 60%" on a night with any window and quitting/relaunching after 17:00 local. → pass when a banner arrives.
7. Quit Wi-Fi, wait, reopen popover: "Off the beat since HH:MM" appears after six hours, icon shows star.slash. → pass (long test; optional).
8. Plain wording: Settings › Wording › Plain. Refresh button reads "Refresh". → pass.
```

- [ ] **Step 3: Full verification**

```bash
scripts/test.sh 2>&1 | tail -3
scripts/build-app.sh
pgrep -x Nightwatch && echo RUNNING
```

Expected: all suites pass; app running from /Applications. Walk `docs/uat.md` items 1 to 5 and 8 and record results in the commit message.

- [ ] **Step 4: Commit and tag**

```bash
git add README.md docs/uat.md
git commit -m "docs: README, UAT checklist"
git tag -a v0.1.0 -m "Guards! Guards!"
```

---

## Self-review against the spec

- §1 success criteria 1–3: Tasks 10, 12, 13. Criterion 4: Tasks 6, 14. Criterion 5: Tasks 1, 12, 16.
- §4.1 modules: Forecast (3), Ephemeris (2), Catalog (4), Events (7–9), Planner (5–6), Alerts (10), Settings (11). SGP4 decision resolved: SatelliteKit 2.1.2.
- §4.2 app components: Scheduler, Location, Store, Thumbnails, Notifier, MenuIcon (Theme), views, login item: Tasks 12–15.
- §4.3 storage paths: Task 11 and Task 12 Store.
- §4.5 planner rules: Task 5 (windows, score weights), Task 6 (eligibility, fit, ranking, best three, stack length shown in Task 14).
- §4.6 alert states and quiet hours: Task 10. §4.7 failure handling: stale icon and offline copy (Tasks 12–13), backoff is replaced by the fixed 30-minute cadence with a 6-hour stale guard, which the spec's failure section allows since no alert fires from stale data.
- §4.8 build: Task 12 script. §4.9 tests: oracles in Tasks 2, 8; edge cases in 5, 10; fixtures in 3, 4, 9.
- §5 UI: popover (13), targets and detail (14), settings and about (15). Notification copy per Notify artboard (10).
- §6 flavour: Copy table in Task 10 only; About turtle in Task 15; release names in Task 16.
- §8 out of scope: no widget, no light-pollution raster, no telescope control.

Type consistency checked: `Copy.hhmm(_:site:)`, `Planner.plan(night:forecast:catalog:constellations:site:fov:rule:)`, `AlertEngine.step(now:tonight:tomorrow:state:settings:forecastFetchedAt:site:copy:)`, `Satellites.visiblePasses(tle:site:from:to:minPeakElevation:)`, `Store.constellation(_:)` are spelled the same in every task that uses them.
