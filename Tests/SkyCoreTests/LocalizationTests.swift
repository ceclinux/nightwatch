import Testing
import Foundation
@testable import SkyCore

@Test func interfaceLanguageResolutionAndPersistence() {
    #expect(AppLanguage.system.resolved(preferredLanguages: ["zh-Hans-CN", "en"]) == .simplifiedChinese)
    #expect(AppLanguage.system.resolved(preferredLanguages: ["zh_CN"]) == .simplifiedChinese)
    #expect(AppLanguage.system.resolved(preferredLanguages: ["zh-SG"]) == .simplifiedChinese)
    #expect(AppLanguage.system.resolved(preferredLanguages: ["en-US", "zh-Hans"]) == .english)
    #expect(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "zh-Hans"]) == .simplifiedChinese)
    #expect(AppLanguage.system.resolved(preferredLanguages: ["zh-Hant-TW", "en"]) == .english)
    #expect(AppLanguage.system.resolved(preferredLanguages: []) == .english)
    #expect(AppLanguage.english.resolved(preferredLanguages: ["zh-Hans"]) == .english)
    #expect(AppLanguage.simplifiedChinese.resolved(preferredLanguages: ["en"]) == .simplifiedChinese)

    let suite = "Nightwatch.LocalizationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(AppLanguage.saved(in: defaults) == .system)
    defaults.set("zh-Hans", forKey: AppLanguage.defaultsKey)
    #expect(AppLanguage.saved(in: defaults) == .simplifiedChinese)
    defaults.set("unknown-future-language", forKey: AppLanguage.defaultsKey)
    #expect(AppLanguage.saved(in: defaults) == .system)
}

@Test func localizedMessagesPreserveAndReorderValues() {
    #expect(L10n.text("Settings", language: .simplifiedChinese) == "设置")
    #expect(L10n.text("Settings", language: .english) == "Settings")
    #expect(L10n.text("NGC 7000", language: .simplifiedChinese) == "NGC 7000")
    #expect(L10n.text("A missing translation", language: .simplifiedChinese) == "A missing translation")
    let name = "院子 {0} {1} 50% 🪐"
    #expect(L10n.format("Use \(30)° for \(name)", language: .simplifiedChinese) == "将院子 {0} {1} 50% 🪐设为 30°")
    #expect(L10n.format("Use \(30)° for \(name)", language: .english) == "Use 30° for 院子 {0} {1} 50% 🪐")
    #expect(L10n.format("Unknown \(name)", language: .simplifiedChinese) == "Unknown \(name)")
}

@Test func translationsKeepAllFormatArguments() throws {
    // A missing resource must fail the test rather than silently passing with English fallback.
    #expect(L10n.chinese.count > 800)
    let numbered = try NSRegularExpression(pattern: #"\{\d+\}"#)
    let printf = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0 #]*(?:\d+)?(?:\.\d+)?(?:ll|l)?[@dfgsu]"#)
    func tokens(_ text: String, _ regex: NSRegularExpression) -> [String] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }.sorted()
    }
    for (key, value) in L10n.chinese {
        #expect(!value.isEmpty)
        #expect(tokens(key, numbered) == tokens(value, numbered), "Interpolation mismatch: \(key)")
        // Percentages after interpolation ("{0}% during…") are not printf format strings.
        if tokens(key, numbered).isEmpty {
            #expect(tokens(key, printf) == tokens(value, printf), "Printf mismatch: \(key)")
        }
    }
}

@Test func generatedCopySwitchesBothWaysWithoutRestarting() {
    L10n.$languageOverride.withValue(.english) {
        #expect(Copy().refresh == "Refresh")
        #expect(Copy.duration(6000) == "1 h 40 min")
        #expect(NumbersGuide.entries.first?.title == "Sky score")
        L10n.$languageOverride.withValue(.simplifiedChinese) {
            #expect(Copy().refresh == "刷新")
            #expect(Copy.duration(6000) == "1 小时 40 分钟")
            #expect(Copy.inPlan(10) == "已列入计划，第 11 项")
            #expect(TargetGroup.nebulae.displayName == "星云")
            #expect(NumbersGuide.entries.first?.title == "天空评分")
            #expect(Bortle.name(4) == "乡村与郊区交界")
            #expect(DewRisk.high.displayName == "高")
            #expect(AuroraLevel.amber.displayName == "橙色")
            #expect(DarknessBand.dark.displayName == "暗")
        }
        #expect(Copy().refresh == "Refresh")
        #expect(NumbersGuide.entries.first?.title == "Sky score")
        #expect(Copy.inPlan(10) == "In the plan, 11th")
    }
}

@Test func chineseKeepsCatalogueIdentifiersAndClassification() throws {
    let english = try L10n.$languageOverride.withValue(.english) { try Catalog.bundled() }
    let chinese = try L10n.$languageOverride.withValue(.simplifiedChinese) { try Catalog.bundled() }
    #expect(!english.objects.isEmpty)
    #expect(english.objects == chinese.objects)
    L10n.$languageOverride.withValue(.simplifiedChinese) {
        #expect(Catalog.typeNames["HII"] == "Emission nebula")
        var target = RankedTarget(id: "NGC7000", name: "NGC 7000", subtitle: "HII in Cyg", group: .nebulae,
                                  raHours: 0, decDeg: 0, sizeArcmin: 120, magnitude: 4, fit: .mosaic,
                                  peakAltDeg: 70, peakTime: Date(), moonSepDeg: 90, moonWashed: false, visibleFraction: 1)
        target.typeName = "Emission nebula"
        #expect(ShootingTips.kind(target) == .emission)
        #expect(target.cardName == "发射星云")
        #expect(target.displaySubtitle == "HII，位于 Cyg")
        #expect(target.matches("发射星云") && target.matches("emission") && target.matches("NGC7000"))
        let moon = RankedTarget(id: "moon", name: "Moon", subtitle: "62% illuminated", group: .planets,
                                raHours: 0, decDeg: 0, sizeArcmin: 30, magnitude: -10, fit: .fits,
                                peakAltDeg: 50, peakTime: Date(), moonSepDeg: 0, moonWashed: false, visibleFraction: 1)
        #expect(moon.displaySubtitle == "照明比例 62%")
        #expect(Copy.brightList([moon]) == "月球 62%")
    }
}

@Test func widgetKeepsTheAppsLanguageAcrossProcessesAndOldSnapshotsStillLoad() throws {
    var snapshot = WidgetSnapshot.sample
    snapshot.languageCode = "zh-Hans"
    snapshot.fetchedAt = Date(timeIntervalSince1970: 0)
    let data = try JSONEncoder().encode(snapshot)
    let restored = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    L10n.$languageOverride.withValue(.english) {
        #expect(restored.interfaceLanguage == .simplifiedChinese)
        #expect(restored.staleText(now: Date(timeIntervalSince1970: 7 * 3600)) == "预报已过 7 小时")
    }
    var oldJSON = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    oldJSON.removeValue(forKey: "languageCode")
    let old = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: oldJSON))
    #expect(old.interfaceLanguage == nil)
}

@Test func localizedCopyNeverChangesClearWindowsOrScores() {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let end = start.addingTimeInterval(8 * 3600)
    let hours = (0..<8).map { i in
        HourlyConditions(time: start.addingTimeInterval(Double(i) * 3600), cloudTotal: i < 2 ? 80 : 10,
                         cloudLow: nil, cloudMid: nil, cloudHigh: nil, tempC: 10, dewPointC: 9,
                         humidityPct: nil, windKmh: 15, gustKmh: nil, visibilityM: nil, seeing: 5, transparency: 5)
    }
    func result(_ language: AppLanguage) -> ([ClearWindow], Int, [LimitingKind]) {
        L10n.$languageOverride.withValue(language) {
            let windows = Planner.windows(hours: hours, darkStart: start, darkEnd: end, rule: GoRule())
            let input = ScoreInputs(darkHours: hours, windows: windows, darkness: (start, end), moonIllumination: 0.8, moonAboveFraction: 1)
            return (windows, Planner.score(input), Planner.limitingFactors(input).map(\.kind))
        }
    }
    let en = result(.english), zh = result(.simplifiedChinese)
    #expect(en.0 == zh.0 && en.1 == zh.1 && en.2 == zh.2)
}

@Test func eventIdentityAndDateFormattingDoNotDependOnTranslation() {
    let site = Site(name: "庭院 {1}", latitude: 54, longitude: -1.5, elevationM: 100, timeZoneID: "UTC", bortle: 5)
    let date = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!
    let en = L10n.$languageOverride.withValue(.english) { Events.conjunctions(at: date, site: site, maxSeparationDeg: 180) }
    let zh = L10n.$languageOverride.withValue(.simplifiedChinese) { Events.conjunctions(at: date, site: site, maxSeparationDeg: 180) }
    #expect(!en.isEmpty && en.map(\.id) == zh.map(\.id))
    #expect(en.map(\.separationDeg) == zh.map(\.separationDeg))
    #expect(en.map(EyeViews.includes) == zh.map(EyeViews.includes))
    L10n.$languageOverride.withValue(.simplifiedChinese) {
        #expect(Copy.dayMonth(date, site: site).contains("10月7日"))
        #expect(Copy.hhmm(date, site: site) == "12:00")
        #expect(Events.day(date, site: site) == "10月7日")
    }
    L10n.$languageOverride.withValue(.english) {
        #expect(Copy.dayMonth(date, site: site) == "Wed 7 Oct")
        #expect(Copy.hhmm(date, site: site) == "12:00")
    }
}
