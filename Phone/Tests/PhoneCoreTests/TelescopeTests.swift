import Testing
import Foundation
import SkyCore
@testable import PhoneCore

@MainActor @Test func choosingAPresetSetsItsFieldOfViewAndRemembersWhich() throws {
    let store = makeStore(clock: Clock(utc(2026, 9, 23, 12)), calls: Calls())
    let preset = try #require(TelescopePresets.shared.first)
    store.setTelescope(presetID: preset.id)
    #expect(store.config.fovPresetID == preset.id)
    #expect(store.config.fov == preset.fov)
}

@MainActor @Test func aTypedFieldBecomesCustomOnlyWhenANumberReallyChanges() throws {
    let store = makeStore(clock: Clock(utc(2026, 9, 23, 12)), calls: Calls())
    let preset = try #require(TelescopePresets.shared.first)
    store.setTelescope(presetID: preset.id)
    store.setFieldOfView(width: preset.fov.widthDeg)               // the same number written back: still the preset
    #expect(store.config.fovPresetID == preset.id)
    store.setFieldOfView(width: preset.fov.widthDeg + 1)
    #expect(store.config.fovPresetID == nil)
    #expect(store.config.fov.widthDeg == preset.fov.widthDeg + 1)
    store.setFieldOfView(width: 0)                                  // never below 0.05 degrees
    #expect(store.config.fov.widthDeg == 0.05)
}

@MainActor @Test func aStricterGoRuleTakesTheNightsWindowAway() async {
    let store = makeStore(clock: Clock(utc(2026, 9, 23, 12)), calls: Calls())
    await store.refresh()
    #expect(store.planning?.tonight.primary != nil)
    store.setGoRule { $0.minHours = 20 }                             // longer than any night
    await store.recompute(now: utc(2026, 9, 23, 12))
    #expect(store.planning?.tonight.primary == nil)
    #expect(store.config.goRule.minHours == 20)
}
