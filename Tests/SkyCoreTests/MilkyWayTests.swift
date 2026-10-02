import Foundation
import Testing
@testable import SkyCore

struct MilkyWayTests {
    let malham = Site(name: "Malham", latitude: 54.07, longitude: -2.15, elevationM: 380, timeZoneID: "Europe/London", bortle: 3)
    let sutherland = Site(name: "Sutherland", latitude: -32.38, longitude: 20.81, elevationM: 1760, timeZoneID: "Africa/Johannesburg", bortle: 1)
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    @Test func fromTheKaroo_TheCoreIsNearlyOverheadOnAWinterNight() {
        let night = ClearWindow(start: date("2026-07-15T18:00:00Z"), end: date("2026-07-16T03:30:00Z"))
        let core = MilkyWay.targets(window: night, site: sutherland, moonWashed: false)[0]
        #expect(core.id == "milky-way-core")
        #expect(core.viewable != nil)
        #expect(core.peakAltDeg > 80)   // 90 − |−32.4 + 29.0| ≈ 86.6 at its highest
        #expect(EyeViews.view(core, bortle: 1) == .nakedEye)
    }

    @Test func fromYorkshire_TheCoreNeverClearsButCygnusIsOverhead() {
        let night = ClearWindow(start: date("2026-08-15T21:30:00Z"), end: date("2026-08-16T03:00:00Z"))
        let both = MilkyWay.targets(window: night, site: malham, moonWashed: false)
        #expect(both[0].viewable == nil)
        #expect(both[1].viewable != nil)
        #expect(both[1].peakAltDeg > 70)   // 90 − |54.1 − 40.3| ≈ 76
        #expect(both[1].name == "The summer Milky Way through Cygnus")
        let why = MilkyWay.coreNeverClears(site: malham, on: date("2026-07-10T12:00:00Z"))
        #expect(why?.hasPrefix("Never above 7° from here") == true)
        #expect(MilkyWay.coreNeverClears(site: malham, on: date("2026-01-10T12:00:00Z")) == nil)   // out of season: no card
        #expect(MilkyWay.coreNeverClears(site: sutherland, on: date("2026-07-10T12:00:00Z")) == nil)
    }

    @Test func aHorizonInTheWayIsGivenAsTheReason() {
        var madrid = Site(name: "Madrid", latitude: 40.4, longitude: -3.7, elevationM: 650, timeZoneID: "Europe/Madrid", bortle: 4)
        #expect(MilkyWay.coreNeverClears(site: madrid, on: date("2026-07-10T12:00:00Z")) == nil)   // about 21° up
        madrid.horizon = [5, 5, 5, 5, 25, 5, 5, 5]
        #expect(MilkyWay.coreNeverClears(site: madrid, on: date("2026-07-10T12:00:00Z"))?.hasPrefix("Never clears your horizon") == true)
    }

    @Test func aBrightMoonDropsItAndTheTipIsForACamera() {
        let night = ClearWindow(start: date("2026-07-15T18:00:00Z"), end: date("2026-07-16T03:30:00Z"))
        let core = MilkyWay.targets(window: night, site: sutherland, moonWashed: true)[0]
        #expect(EyeViews.view(core, bortle: 1) == nil)
        let tip = ShootingTips.tip(for: core, presetID: "dwarf-mini", presetName: "DWARF mini", stackMinutes: 300, site: sutherland)
        #expect(tip.title == "How to shoot this with a camera and wide lens")
        #expect(tip.rows.map(\.label) == ["Kit", "Lens", "Exposure", "ISO", "When"])
        #expect(tip.copyLine == nil)
    }
}
