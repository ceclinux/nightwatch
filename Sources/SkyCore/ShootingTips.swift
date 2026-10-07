import Foundation

/// "How to shoot this" on a target's detail page (v0.6.7): filter, exposure and frames for the user's own instrument and
/// this kind of target, sized to tonight's clear window. Every number comes from the maker's own material, named in
/// `source`; where none was found (planets, ISO on a camera) the tip gives guidance without numbers.
public struct ShootingTip: Equatable, Sendable {
    public var title: String
    public var rows: [Row]
    public var source: String?
    /// The settings as one line to paste into the telescope's app (#61): target, telescope and numbers only. Nil where the
    /// maker publishes no numbers, and then no copy icon is shown.
    public var copyLine: String? = nil
    /// The card's SF Symbol: a camera for telescope settings, binoculars or an eye for How to see this.
    public var symbol = "camera.aperture"
    public struct Row: Equatable, Sendable {
        public var label: String
        public var text: String
        public init(_ label: String, _ text: String) { self.label = label; self.text = text }
    }
}

public enum ShootingTips {
    /// What kind of light the target gives, which decides the filter.
    enum Kind: Equatable { case emission, broadband, nebulaUnknown, moon, planet, constellation, star }

    static func kind(_ t: RankedTarget) -> Kind {
        if t.id == "moon" { return .moon }
        if t.id.hasPrefix("planet-") { return .planet }
        switch t.group {
        case .constellations: return .constellation
        case .stars: return .star
        case .galaxies, .clusters: return t.typeName == "Cluster with nebula" ? .emission : .broadband
        default: break
        }
        switch t.typeName {
        case "Emission nebula", "Planetary nebula", "Supernova remnant", "Cluster with nebula": return .emission
        case "Reflection nebula", "Dark nebula": return .broadband
        default: return .nebulaUnknown
        }
    }

    /// A plan row's kit, from the maker's figures: "Duo-Band · 200 × 30 s". Nil where the tips give no filter name, and for
    /// the Moon, planets, stars and constellations, whose tips carry no deep-sky filter or frames (Saturn read "Duo-Band or
    /// Astro · 200 × 30 s", owner's UAT, 29 September 2026).
    public static func planKit(_ t: RankedTarget, presetID: String?) -> String? {
        let k = kind(t)
        guard [.emission, .broadband, .nebulaUnknown].contains(k) else { return nil }
        switch presetID {
        case "dwarf-mini", "dwarf-3":
            return "\(k == .emission ? "Duo-Band" : (k == .broadband ? "Astro" : L10n.text("Duo-Band or Astro"))) · 200 × 30 s"
        case "draco":   // filter names only: DWARFLAB has published no frame counts for it
            return k == .emission ? "Hα + O III" : (k == .broadband ? L10n.text("Astronomy filter") : L10n.text("Hα + O III or Astronomy filter"))
        case "seestar-s50":
            let filter = k == .emission ? L10n.text("Light-pollution filter on · ") : (k == .broadband ? L10n.text("Light-pollution filter off · ") : "")
            return filter + "1,000 × 10 s"
        case "seestar-s30", "seestar-s30-pro", "seestar-s50-pro":   // filter only: ZWO has published no frame length for them
            return k == .emission ? L10n.text("Light-pollution filter on") : (k == .broadband ? L10n.text("Light-pollution filter off") : nil)
        default:
            return nil
        }
    }

    /// `stackMinutes`: how long the target is up inside the night's clear window; nil when there is no clear window.
    /// `night`: "tonight", or "tomorrow night" while the Targets window shows tomorrow (owner's UAT, 30 September 2026).
    public static func tip(for t: RankedTarget, presetID: String?, presetName: String?, stackMinutes: Double?, site: Site,
                           night: String = L10n.text("tonight")) -> ShootingTip {
        if MilkyWay.isMilkyWay(t.id) { return milkyWayTip(t, site: site) }
        let k = kind(t)
        var rows: [ShootingTip.Row] = []
        var source: String?
        let name = presetName ?? L10n.text("your telescope")
        let hours = stackMinutes.map { String(format: "%.1f h", $0 / 60).replacingOccurrences(of: ".0 h", with: " h") }
        func frames(_ seconds: Double) -> Int? { stackMinutes.map { Int(($0 * 60 / seconds).rounded()) } }

        // The same for every instrument: no maker publishes star settings, so this is guidance without numbers.
        if k == .star {
            rows.append(.init(L10n.text("Use"), L10n.text("A bright point for focusing, plate-solving and checking the mount's tracking, rather than a subject on its own.")))
            rows.append(.init(L10n.text("Exposure"), L10n.text("Keep frames short, so it stays a sharp point instead of a bloated disc.")))
            if let v = t.viewable {
                rows.append(.init(L10n.text("When"), L10n.format("Up and clear from \(Copy.hhmm(v.start, site: site)); highest at \(Copy.hhmm(t.peakTime, site: site)).")))
            }
            return ShootingTip(title: L10n.format("How to shoot this with \(presetName == nil ? L10n.text("your telescope") : L10n.format("your \(name)"))"), rows: rows, source: nil)
        }

        switch presetID {
        case "dwarf-mini", "dwarf-3":
            source = L10n.text("Settings from DWARFLAB's user manual; Mega Stack from DWARFLAB's help pages.")
            switch k {
            case .moon:
                rows.append(.init(L10n.text("Mode"), L10n.text("Use the Moon mode: it sets focus, exposure and gain for you (about 1/250 s, gain 0, Astro filter).")))
                rows.append(.init(L10n.text("Frames"), L10n.text("Start with 20–30 images.")))
            case .planet:
                rows.append(.init(L10n.text("Expect"), L10n.text("A small bright disc at this focal length; Jupiter's and Saturn's larger moons show as points.")))
                source = nil
            case .constellation:
                rows.append(.init(L10n.text("Framing"), L10n.text("Far larger than the field of view: use a wide-angle lens, or pick one bright object in it.")))
                source = nil
            default:
                rows.append(.init(L10n.text("Filter"), filterText(k, dualBand: "Duo-Band", broadband: "Astro")))
                rows.append(.init(L10n.text("Exposure"), L10n.text("15–60 s per frame at gain 60–80.")))
                if let n = frames(30), let h = hours {
                    rows.append(.init(L10n.text("Frames"), L10n.format("200–400 recommended. At 30 s a frame, for example, \(n) frames fill the \(h) it is up \(night).")))
                } else {
                    rows.append(.init(L10n.text("Frames"), L10n.text("200–400 recommended.")))
                }
                // Owner, 2 October 2026: a favourite already brings a target back each clear night, so the one help needed
                // across nights is this. DWARFLAB's help names the same target and filter; a matching exposure and gain is
                // the safe choice (a third-party guide says Mega Stack needs it too).
                rows.append(.init(L10n.text("Nights"), L10n.text("To join several nights in Mega Stack, shoot every night with the same filter, ")
                                  + L10n.text("and keep one exposure and gain, to be safe. Trailed stars in any night can stop the stack.")))
            }
        case "draco":
            // #69: DWARFLAB publishes the Draco's filters but, as of 29 September 2026, no manual with exposure, gain or
            // frame figures, so the tip names the filters and gives the rest without numbers (and no copy icon).
            switch k {
            case .moon:
                rows.append(.init(L10n.text("Exposure"), L10n.text("The Moon is bright: use short exposures and check the histogram.")))
            case .planet:
                rows.append(.init(L10n.text("Expect"), L10n.text("A small bright disc at this focal length; Jupiter's and Saturn's larger moons show as points.")))
            case .constellation:
                rows.append(.init(L10n.text("Framing"), L10n.text("Far larger than the field of view: use a wide-angle lens, or pick one bright object in it.")))
            default:
                source = L10n.text("Filters from DWARFLAB's Draco product page; it has published no exposure settings yet.")
                rows.append(.init(L10n.text("Filter"), filterText(k, dualBand: L10n.text("Hα + O III dual-narrowband filter"), broadband: L10n.text("Astronomy filter"))))
                rows.append(.init(L10n.text("Exposure"), L10n.text("Single frames can run up to 300 s; DWARFLAB has not yet published a recommended exposure or gain.")))
                if let h = hours { rows.append(.init(L10n.text("Frames"), L10n.format("It is up and clear for \(h) \(night)."))) }
            }
        case "seestar-s50":
            source = L10n.text("Filters and frame length from ZWO's Seestar S50 FAQ.")
            switch k {
            case .moon:
                rows.append(.init(L10n.text("Mode"), L10n.text("Use Lunar mode: it finds and tracks the Moon for you.")))
            case .planet:
                rows.append(.init(L10n.text("Expect"), L10n.text("A small bright disc at this focal length; Jupiter's and Saturn's larger moons show as points.")))
                source = nil
            case .constellation:
                rows.append(.init(L10n.text("Framing"), L10n.text("Far larger than the field of view: use a wide-angle lens, or pick one bright object in it.")))
                source = nil
            default:
                rows.append(.init(L10n.text("Filter"), filterText(k, dualBand: L10n.text("Light-pollution filter on"), broadband: L10n.text("Light-pollution filter off (UV/IR cut)"))))
                rows.append(.init(L10n.text("Exposure"), L10n.text("10 s frames; the Seestar stacks them as it goes.")))
                if let n = frames(10), let h = hours {
                    rows.append(.init(L10n.text("Frames"), L10n.format("Let it stack while it is up: \(h) is about \(n) frames.")))
                } else {
                    rows.append(.init(L10n.text("Frames"), L10n.text("Let it stack for as long as you can.")))
                }
            }
        case "seestar-s30", "seestar-s30-pro", "seestar-s50-pro":
            // ZWO's pages for these three (read 7 October 2026) name the same light-pollution filter as the S50's but give no
            // alt-az frame length, only EQ mode's 60 s cap, so the tip quotes that cap and nothing else (and no copy icon),
            // as for the Draco.
            switch k {
            case .moon:
                // ZWO names it Solar System mode for these models (the S30's page, the S30 Pro's FAQ and its
                // shooting-modes tutorial); "Lunar mode" is the original S50's.
                rows.append(.init(L10n.text("Mode"), L10n.text("Use Solar System mode and choose the Moon.")))
            case .planet:
                rows.append(.init(L10n.text("Expect"), L10n.text("A small bright disc at this focal length; Jupiter's and Saturn's larger moons show as points.")))
            case .constellation:
                rows.append(.init(L10n.text("Framing"), L10n.text("Far larger than the field of view: use a wide-angle lens, or pick one bright object in it.")))
            default:
                let page = ["seestar-s30": L10n.text("Seestar S30 page"), "seestar-s50-pro": L10n.text("Seestar S50 Pro page")][presetID ?? ""] ?? L10n.text("Seestar S30 Pro FAQ")
                source = L10n.format("Filter and EQ-mode limit from ZWO's \(page); it publishes no frame length.")
                rows.append(.init(L10n.text("Filter"), filterText(k, dualBand: L10n.text("Light-pollution filter on"), broadband: L10n.text("Light-pollution filter off (UV/IR cut)"))))
                rows.append(.init(L10n.text("Exposure"), L10n.text("Short frames in alt-az mode, up to 60 s in EQ mode; the Seestar stacks them as it goes.")))
                if let h = hours { rows.append(.init(L10n.text("Frames"), L10n.format("It is up and clear for \(h) \(night)."))) }
            }
        case "dslr-apsc-200":
            source = L10n.text("The untracked limit comes from the 500 and NPF rules; tracked times are typical ranges, not a maker's figure.")
            switch k {
            case .moon:
                rows.append(.init(L10n.text("Exposure"), L10n.text("The Moon is bright: use short exposures and check the histogram.")))
                source = nil
            case .planet:
                rows.append(.init(L10n.text("Expect"), L10n.text("A tiny disc at 200 mm; Jupiter's larger moons show as points.")))
                source = nil
            default:
                rows.append(.init(L10n.text("Exposure"), L10n.text("On a star tracker, 60–120 s in the suburbs and longer at a dark site. Without one, under about 1.5 s before stars trail.")))
                if let h = hours, let n = frames(120) {
                    rows.append(.init(L10n.text("Frames"), L10n.format("Take as many as the time it is up allows: \(h) is about \(n) × 120 s on a tracker.")))
                }
                if k == .emission || k == .nebulaUnknown {
                    rows.append(.init(L10n.text("Filter"), L10n.text("A dual-band or light-pollution filter lifts an emission nebula out of a bright sky.")))
                }
            }
        default:
            switch k {
            case .moon, .planet, .constellation:
                rows.append(.init(L10n.text("Tip"), L10n.text("Check your instrument's manual for its Moon, planet or wide-field settings.")))
            default:
                rows.append(.init(L10n.text("Filter"), filterText(k, dualBand: L10n.text("A dual-band or narrowband filter"), broadband: L10n.text("No filter, or a light-pollution filter only"))))
                rows.append(.init(L10n.text("Exposure"), L10n.text("Check your telescope's manual for exposure and gain.")))
                if let h = hours { rows.append(.init(L10n.text("Frames"), L10n.format("It is up and clear for \(h) \(night)."))) }
            }
        }

        // Owner, 2 October 2026: one line for every telescope, naming none and quoting no maker's numbers.
        if [.emission, .broadband, .nebulaUnknown].contains(k) {
            rows.append(.init(L10n.text("EQ mode"), L10n.text("Long frames and stacks over several nights come out best in your telescope's EQ mode, ")
                              + L10n.text("if it has one: in alt-az mode the sky slowly turns in the frame.")))
        }
        if let v = t.viewable, k != .constellation {
            rows.append(.init(L10n.text("When"), L10n.format("Start at \(Copy.hhmm(v.start, site: site)), when it is clear and high enough; it is best at \(Copy.hhmm(t.peakTime, site: site)).")))
        }
        var tip = ShootingTip(title: L10n.format("How to shoot this with \(presetName == nil ? L10n.text("your telescope") : L10n.format("your \(name)"))"), rows: rows, source: source)
        tip.copyLine = copyNumbers(k, presetID: presetID).map { numbers in
            let what = [t.catalogueID, t.commonName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return "\(what.isEmpty ? t.name : what) · \(presetName ?? name): \(numbers)"
        }
        return tip
    }

    /// The Milky Way (#114, owner-approved mock-up): a camera and wide lens whatever the telescope, since even the widest
    /// smart telescope sees a few degrees of a band that spans the sky.
    static func milkyWayTip(_ t: RankedTarget, site: Site) -> ShootingTip {
        let north = site.latitude >= 0, core = t.id == "milky-way-core"
        let season = core ? (north ? L10n.text("late spring to late summer") : L10n.text("autumn to early spring")) : (north ? L10n.text("summer and autumn") : "winter")
        var rows: [ShootingTip.Row] = [
            .init(L10n.text("Kit"), L10n.text("A camera with a wide lens on a tripod: a telescope sees only a few degrees of it.")),
            .init(L10n.text("Lens"), L10n.text("14–24 mm, as wide open as it goes.")),
            .init(L10n.text("Exposure"), L10n.text("Untracked, up to about 20 s at 24 mm and 35 s at 14 mm on a full-frame camera before stars trail (the 500 rule); ")
                  + L10n.text("two-thirds of that on APS-C, and about half for stars sharp at full size (the NPF rule).")),
            .init("ISO", "1600–6400."),
        ]
        let best = L10n.format("Best in \(season), on a moonless night.")
        if let v = t.viewable {
            rows.append(.init(L10n.text("When"), L10n.format("Up from \(Copy.hhmm(v.start, site: site)); highest at \(Copy.hhmm(t.peakTime, site: site)), \(Int(t.peakAltDeg.rounded()))° up. \(best)")))
        } else {
            rows.append(.init(L10n.text("When"), best))
        }
        return ShootingTip(title: L10n.text("How to shoot this with a camera and wide lens"), rows: rows, source: L10n.text("Exposure limits from the 500 and NPF rules."))
    }

    /// The numbers the card gives, without the explanations; nil where it gives none.
    static func copyNumbers(_ k: Kind, presetID: String?) -> String? {
        switch presetID {
        case "dwarf-mini", "dwarf-3":
            switch k {
            case .moon: return L10n.text("Moon mode, about 1/250 s at gain 0, Astro filter, 20–30 images")
            case .planet, .constellation, .star: return nil
            default:
                let filter = k == .emission ? "Duo-Band" : (k == .broadband ? "Astro" : L10n.text("Duo-Band or Astro"))
                return L10n.format("\(filter) filter, 15–60 s at gain 60–80, 200–400 frames")
            }
        case "seestar-s50":
            switch k {
            case .emission: return L10n.text("light-pollution filter on, 10 s frames")
            case .broadband: return L10n.text("light-pollution filter off, 10 s frames")
            case .nebulaUnknown: return L10n.text("light-pollution filter on if it glows red, off if not, 10 s frames")
            default: return nil
            }
        case "dslr-apsc-200":
            switch k {
            case .moon, .planet, .star, .constellation: return nil
            case .emission, .nebulaUnknown: return L10n.text("dual-band or light-pollution filter, 60–120 s on a star tracker, under about 1.5 s without one")
            default: return L10n.text("60–120 s on a star tracker, under about 1.5 s without one")
            }
        default:
            return nil
        }
    }

    /// "How to see this" (owner's UAT, 29 September 2026): a target opened from Eyes and binoculars gets what it looks like,
    /// where and when to look, and how to look, instead of telescope settings. `constellation`: the full name of the one it is
    /// in, when known.
    public static func eyeTip(for t: RankedTarget, eye: EyeView, constellation: String?, moonIllumination: Double, moonUp: Bool,
                              site: Site, night: String = L10n.text("tonight")) -> ShootingTip {
        var rows = [ShootingTip.Row(L10n.text("Looks like"), Copy.eyeLook(t, eye) + ".")]
        let az = Ephemeris.altAz(raHours: t.raHours, decDeg: t.decDeg, at: t.peakTime, site: site).az
        let direction = [L10n.text("north"), L10n.text("north-east"), L10n.text("east"), L10n.text("south-east"), L10n.text("south"), L10n.text("south-west"), L10n.text("west"), L10n.text("north-west")][Int((az / 45).rounded()) % 8]
        let height = t.peakAltDeg >= 60 ? L10n.text("high in the") : (t.peakAltDeg < 25 ? L10n.text("low in the") : L10n.text("in the"))
        let whereText = L10n.format("\(height) \(direction) at \(Copy.hhmm(t.peakTime, site: site))")
        if let c = constellation, t.group != .constellations {
            rows.append(.init(L10n.text("Where"), L10n.format("In \(c), \(whereText).")))
        } else {
            rows.append(.init(L10n.text("Where"), whereText.prefix(1).uppercased() + whereText.dropFirst() + "."))
        }
        let best = L10n.format("best at \(Copy.hhmm(t.peakTime, site: site)), \(Int(t.peakAltDeg.rounded()))° up.")
        rows.append(.init(L10n.text("When"), t.viewable.map { L10n.format("Up from \(Copy.hhmm($0.start, site: site)); \(best)") } ?? best.prefix(1).uppercased() + best.dropFirst()))
        // Bright points (the Moon, planets, stars) need no dark adaptation or averted vision; faint ones do.
        let faint = t.id != "moon" && ![.planets, .stars].contains(t.group)
        let adapt = L10n.text("give your eyes 20 minutes away from lights. Looking slightly to one side of it shows faint detail better.")
        switch (eye, faint) {
        case (.binoculars, true): rows.append(.init(L10n.text("Tips"), L10n.format("Brace your binoculars on a wall or a tripod, and \(adapt)")))
        case (.binoculars, false): rows.append(.init(L10n.text("Tips"), L10n.text("Brace your binoculars on a wall or a tripod to hold the view steady.")))
        case (.nakedEye, true): rows.append(.init(L10n.text("Tips"), L10n.text("Find somewhere away from lights and ") + adapt))
        case (.nakedEye, false): break
        }
        if faint, moonUp, moonIllumination >= 0.5 {
            rows.append(.init(L10n.text("Moon"), L10n.format("The Moon is \(Int((moonIllumination * 100).rounded()))% lit \(night), which makes it harder to see.")))
        }
        var tip = ShootingTip(title: L10n.format("How to see this with \(eye == .binoculars ? L10n.text("Binoculars").lowercased() : L10n.text("the naked eye"))"), rows: rows, source: nil)
        tip.symbol = eye == .binoculars ? "binoculars" : "eye"
        return tip
    }

    /// "How to shoot this" for an event (v1.0.1). No maker publishes settings for these, so it is guidance without numbers.
    public static func tip(for e: SkyEvent, fov: FieldOfView, presetName: String?, site: Site) -> ShootingTip {
        var rows: [ShootingTip.Row] = []
        switch e.kind {
        case .meteorShower:
            rows.append(.init(L10n.text("Kit"), L10n.text("A telescope's narrow field catches few meteors: use a camera with a wide lens on a tripod.")))
            rows.append(.init(L10n.text("Aim"), L10n.text("About 45° from the radiant, high in the darkest part of the sky.")))
            rows.append(.init(L10n.text("Exposure"), L10n.text("Shoot continuously, each frame short enough that the stars stay points (the 500 rule), and keep the frames that caught one.")))
        case .issPass:
            rows.append(.init(L10n.text("Kit"), L10n.text("Too fast for a smart telescope to follow: photograph it as a streak with a wide lens on a tripod.")))
            rows.append(.init(L10n.text("Timing"), L10n.format("Start a long exposure, or a run of short ones, just before it appears at \(Copy.hhmm(e.time, site: site)), and stop as it goes.")))
        case .comet:
            rows.append(.init(L10n.text("Filter"), filterText(.broadband, dualBand: L10n.text("A dual-band filter"), broadband: L10n.text("No filter, or a light-pollution filter only"))))
            rows.append(.init(L10n.text("Stacking"), L10n.text("It moves against the stars through the night, so keep the stack short, or align the frames on the comet when you stack.")))
        case .conjunction:
            rows.append(.init(L10n.text("Framing"), e.fits == true ? L10n.text("Both fit in your field of view: centre the frame between them.")
                                              : L10n.text("Wider than your field of view: use a wider lens, or shoot each on its own.")))
        case .lunarEclipse:
            rows.append(.init(L10n.text("Mode"), L10n.text("Start in your telescope's Moon mode. The eclipsed Moon is far dimmer, so lengthen the exposure as it darkens.")))
        case .solarEclipse:
            rows.append(.init(L10n.text("Safety"), L10n.text("Never point a telescope or camera at the Sun without a certified solar filter over the front.")))
        case .occultation:
            rows.append(.init(L10n.text("Watch"), L10n.text("Be watching a few minutes early: at the Moon's dark edge a star goes out in an instant, and comes back as suddenly.")))
            rows.append(.init(L10n.text("Record"), L10n.text("Your telescope's Moon mode, as video or a run of short exposures, catches the moment; the Moon fills much of a small frame.")))
        }
        if let b = e.best, e.kind != .issPass, e.kind != .occultation { rows.append(.init(L10n.text("When"), L10n.format("Best at \(Copy.hhmm(b, site: site))."))) }
        // Meteors and the ISS are camera work, so their title does not name the telescope.
        if e.kind == .occultation { return ShootingTip(title: L10n.text("How to see this"), rows: rows, source: nil) }
        let title = e.kind == .meteorShower || e.kind == .issPass ? L10n.text("How to shoot this")
                  : L10n.format("How to shoot this with \(presetName.map { L10n.format("your \($0)") } ?? L10n.text("your telescope"))")
        return ShootingTip(title: title, rows: rows, source: nil)
    }

    static func filterText(_ k: Kind, dualBand: String, broadband: String) -> String {
        switch k {
        case .emission: L10n.format("\(dualBand): it passes the hydrogen-alpha and oxygen-III light an emission nebula gives off.")
        case .broadband: L10n.format("\(broadband): this target's light spans the whole spectrum, so a narrow filter would cut most of it.")
        default: L10n.format("\(dualBand) if it glows red (an emission nebula); \(broadband) if it is a reflection or dark nebula.")
        }
    }
}
