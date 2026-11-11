import Testing
import Foundation
import SkyCore
@testable import PhoneCore

@Test func theSurveyRequestIsTheMacsRequest() {
    let fov = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
    let url = SurveyThumbnail.url(raHours: 5.5, decDeg: -5.4, sizeArcmin: 85, fov: fov).absoluteString
    #expect(url.hasPrefix("https://alasky.cds.unistra.fr/hips-image-services/hips2fits?"))
    #expect(url.contains("hips=CDS/P/DSS2/color"))
    #expect(url.contains("ra=82.50000"))
    #expect(url.contains("dec=-5.40000"))
    #expect(url.contains("width=480"))
    #expect(url.contains("height=274"))      // 480 × 1.2 / 2.1
}

@Test func anObjectBiggerThanTheFieldIsShownWholeAtOneAndAHalfTimesItsSize() {
    let fov = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
    #expect(SurveyThumbnail.fovDeg(sizeArcmin: 30, fov: fov) == 2.1)             // fits: the field of view
    #expect(abs(SurveyThumbnail.fovDeg(sizeArcmin: 240, fov: fov) - 6.0) < 1e-9) // 4° × 1.5
}

@Test func tonightsPageShowsAtMostThreePicksWithTheirBestTimes() throws {
    let p = try plans(cloud: 5)
    let model = TonightModel.make(plan: p.tonight, tomorrow: p.tomorrow, forecast: forecast(fetchedAt: utc(2026, 9, 23, 12)),
                                  site: sheffield, config: .default)
    #expect(model.picks.count <= 3)
    #expect(model.picksHeading == (model.picks.isEmpty ? "UP TONIGHT" : "BEST TONIGHT"))
    for p in model.picks { #expect(!p.best.hasPrefix("Best ")) }   // the heading says it
}

@Test func aPicksBestLineSaysWhichWayToLookAsTheMacDoes() throws {
    let p = try plans(cloud: 5)
    let t = try #require(p.tonight.targets.first)
    let pick = TargetPick.make(t, site: sheffield, fov: FieldOfView(widthDeg: 2.1, heightDeg: 1.2))
    #expect(pick.best == "\(Copy.hhmm(t.peakTime, site: sheffield)) · \(Copy.peakHeight(t, site: sheffield))")
    #expect(pick.best.hasSuffix("overhead") || pick.best.contains("° in the "))
}

@Test func theSharpPictureIsTheMacsRequestAtSixteenHundredAndOnlyForDeepSkyTargets() throws {
    let p = try plans(cloud: 5)
    let fov = FieldOfView(widthDeg: 2.1, heightDeg: 1.2)
    let deep = try #require(p.tonight.targets.first { [.nebulae, .galaxies, .clusters].contains($0.group) })
    let sharp = try #require(TargetPick.sharp(deep, site: sheffield, fov: fov))
    let q = URLComponents(url: sharp.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(q.first { $0.name == "width" }?.value == "1600")
    #expect(q.first { $0.name == "hips" }?.value == "CDS/P/DSS2/color")
    #expect(sharp.cacheName.hasPrefix("sharp-"))
    let constellation = try #require(p.tonight.targets.first { $0.group == .constellations })
    #expect(TargetPick.sharp(constellation, site: sheffield, fov: fov) == nil)
}
