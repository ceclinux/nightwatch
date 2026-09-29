import Foundation

/// "What the numbers mean" (#59, owner-approved mock-up, 29 September 2026): every term the popover and the target cards
/// show, explained plainly, one step away. Terms stay where they are; this is the one place that says what they mean. The
/// figures here are the app's own (Planner.score, GoRule, dewRisk, frameFit), so change both together.
public struct GuideEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
}

public enum NumbersGuide {
    public static let entries: [GuideEntry] = [
        GuideEntry(id: "score", title: "Sky score",
                   body: "How good tonight is for imaging from where you are, out of 100. Cloud during darkness counts most: 60 points, or 75 when there is no seeing forecast. Then the Moon (15), seeing and transparency together (15), and calm, dry air (10). “Held back by” names what cost the most."),
        GuideEntry(id: "rule", title: "Go rule and clear window",
                   body: "When Nightwatch calls a night clear: an unbroken run of at least 3 hours inside astronomical darkness with cloud at or under 25%. The clear window is that run. Targets are listed when they are at least 30° up in it. All three numbers are yours to change in Settings › Go rule. Clear sky by hour shows each hour’s cloud: a full bar is clear."),
        GuideEntry(id: "dark", title: "Dark",
                   body: "Astronomical darkness: the Sun more than 18° below the horizon, when the sky is as dark as it gets. In a British midsummer there is none, which is what Bright nights in Settings is for."),
        GuideEntry(id: "moon", title: "Moon",
                   body: "How much of it is lit, and when it is up during darkness. A bright Moon near a faint target washes it out: those are marked Moon-washed. The Targets window gives the next run of moonless nights."),
        GuideEntry(id: "seeing", title: "Seeing",
                   body: "How steady the air is, in arcseconds (″), from 7Timer. Smaller is sharper: about 1″ is excellent, above 2.5″ blurs fine detail. It matters most for planets and small galaxies."),
        GuideEntry(id: "transparency", title: "Transparency",
                   body: "How clear the air is to faint light: haze, dust and thin high cloud dim nebulae and galaxies even when the sky looks clear. From 7Timer."),
        GuideEntry(id: "wind", title: "Wind and dew risk",
                   body: "Wind above 10 km/h starts to cost points, the most it can cost by 40 km/h, since a small telescope shakes in it. Dew risk is how close the air comes to its dew point: within 2 °C is High (fit the dew heater), within 4 °C Medium."),
        GuideEntry(id: "bortle", title: "Bortle",
                   body: "How dark your sky is, from 1 (pristine) to 9 (inner city). Your site’s class is set in Settings; dark sites show theirs, so you can see what a drive would gain."),
        GuideEntry(id: "eq", title: "EQ tilt",
                   body: "The angle to set an equatorial mount’s polar axis: your latitude, pointed at true north (not magnetic north), or true south in the southern hemisphere."),
        GuideEntry(id: "chips", title: "Frame and Moon chips",
                   body: "Fills 28% of frame: how much of your telescope’s field it covers. Small in frame: under 5′ across, a speck. Mosaic: bigger than your field; shoot it in panels or choose part of it. Moon-washed and Near Moon: the Moon will dim it tonight. Naked eye and Binoculars: how it can be seen without a telescope."),
    ]
}
