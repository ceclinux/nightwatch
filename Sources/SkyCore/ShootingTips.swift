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

    /// The shortest worthwhile stack for a deep-sky target (#57). A DWARF: its manual's 200 frames (the low end of 200–400)
    /// at 30 s, 100 minutes. A Seestar stacks as it goes with ZWO's 10 s frames and names no count, so the owner's rule of
    /// thumb for deep sky, about 1,000 frames (29 September 2026): 167 minutes. Nil for a camera or a custom telescope;
    /// Tonight's plan then gives a target the time it is well placed.
    public static func stackMinutes(presetID: String?) -> Double? {
        switch presetID {
        case "dwarf-mini", "dwarf-3": 200 * 30 / 60
        case "seestar-s50": 1000 * 10 / 60
        default: nil
        }
    }

    /// A plan slot's kit, from the same maker figures: "Duo-Band · 200 × 30 s". Nil where the tips give no filter name.
    public static func planKit(_ t: RankedTarget, presetID: String?) -> String? {
        let k = kind(t)
        switch presetID {
        case "dwarf-mini", "dwarf-3":
            return "\(k == .emission ? "Duo-Band" : (k == .broadband ? "Astro" : "Duo-Band or Astro")) · 200 × 30 s"
        case "draco":   // filter names only: DWARFLAB has published no frame counts for it
            return k == .emission ? "Hα + O III" : (k == .broadband ? "Astronomy filter" : "Hα + O III or Astronomy filter")
        case "seestar-s50":
            let filter = k == .emission ? "Light-pollution filter on · " : (k == .broadband ? "Light-pollution filter off · " : "")
            return filter + "1,000 × 10 s"
        default:
            return nil
        }
    }

    /// `stackMinutes`: how long the target is up inside tonight's clear window, up to 3 h; nil when there is no clear window.
    public static func tip(for t: RankedTarget, presetID: String?, presetName: String?, stackMinutes: Double?, site: Site) -> ShootingTip {
        let k = kind(t)
        var rows: [ShootingTip.Row] = []
        var source: String?
        let name = presetName ?? "your telescope"
        let hours = stackMinutes.map { String(format: "%.1f h", $0 / 60).replacingOccurrences(of: ".0 h", with: " h") }
        func frames(_ seconds: Double) -> Int? { stackMinutes.map { Int(($0 * 60 / seconds).rounded()) } }

        // The same for every instrument: no maker publishes star settings, so this is guidance without numbers.
        if k == .star {
            rows.append(.init("Use", "A bright point for focusing, plate-solving and checking the mount's tracking, rather than a subject on its own."))
            rows.append(.init("Exposure", "Keep frames short, so it stays a sharp point instead of a bloated disc."))
            if let v = t.viewable {
                rows.append(.init("When", "Up and clear from \(Copy.hhmm(v.start, site: site)); highest at \(Copy.hhmm(t.peakTime, site: site))."))
            }
            return ShootingTip(title: "How to shoot this with \(presetName == nil ? "your telescope" : "your \(name)")", rows: rows, source: nil)
        }

        switch presetID {
        case "dwarf-mini", "dwarf-3":
            source = "Settings from DWARFLAB's user manual."
            switch k {
            case .moon:
                rows.append(.init("Mode", "Use the Moon mode: it sets focus, exposure and gain for you (about 1/250 s, gain 0, Astro filter)."))
                rows.append(.init("Frames", "Start with 20–30 images."))
            case .planet:
                rows.append(.init("Expect", "A small bright disc at this focal length; Jupiter's and Saturn's larger moons show as points."))
                source = nil
            case .constellation:
                rows.append(.init("Framing", "Far larger than the field of view: use a wide-angle lens, or pick one bright object in it."))
                source = nil
            default:
                rows.append(.init("Filter", filterText(k, dualBand: "Duo-Band", broadband: "Astro")))
                rows.append(.init("Exposure", "15–60 s per frame at gain 60–80."))
                if let n = frames(30), let h = hours {
                    rows.append(.init("Frames", "200–400 recommended. At 30 s a frame, for example, \(n) frames fill the \(h) it is up tonight."))
                } else {
                    rows.append(.init("Frames", "200–400 recommended."))
                }
            }
        case "draco":
            // #69: DWARFLAB publishes the Draco's filters but, as of 29 September 2026, no manual with exposure, gain or
            // frame figures, so the tip names the filters and gives the rest without numbers (and no copy icon).
            switch k {
            case .moon:
                rows.append(.init("Exposure", "The Moon is bright: use short exposures and check the histogram."))
            case .planet:
                rows.append(.init("Expect", "A small bright disc at this focal length; Jupiter's and Saturn's larger moons show as points."))
            case .constellation:
                rows.append(.init("Framing", "Far larger than the field of view: use a wide-angle lens, or pick one bright object in it."))
            default:
                source = "Filters from DWARFLAB's Draco product page; it has published no exposure settings yet."
                rows.append(.init("Filter", filterText(k, dualBand: "Hα + O III dual-narrowband filter", broadband: "Astronomy filter")))
                rows.append(.init("Exposure", "Single frames can run up to 300 s; DWARFLAB has not yet published a recommended exposure or gain."))
                if let h = hours { rows.append(.init("Frames", "It is up and clear for \(h) tonight.")) }
            }
        case "seestar-s50":
            source = "Filters and frame length from ZWO's Seestar S50 FAQ."
            switch k {
            case .moon:
                rows.append(.init("Mode", "Use Lunar mode: it finds and tracks the Moon for you."))
            case .planet:
                rows.append(.init("Expect", "A small bright disc at this focal length; Jupiter's and Saturn's larger moons show as points."))
                source = nil
            case .constellation:
                rows.append(.init("Framing", "Far larger than the field of view: use a wide-angle lens, or pick one bright object in it."))
                source = nil
            default:
                rows.append(.init("Filter", filterText(k, dualBand: "Light-pollution filter on", broadband: "Light-pollution filter off (UV/IR cut)")))
                rows.append(.init("Exposure", "10 s frames; the Seestar stacks them as it goes."))
                if let n = frames(10), let h = hours {
                    rows.append(.init("Frames", "Let it stack while it is up: \(h) is about \(n) frames."))
                } else {
                    rows.append(.init("Frames", "Let it stack for as long as you can."))
                }
            }
        case "dslr-apsc-200":
            source = "The untracked limit comes from the 500 and NPF rules; tracked times are typical ranges, not a maker's figure."
            switch k {
            case .moon:
                rows.append(.init("Exposure", "The Moon is bright: use short exposures and check the histogram."))
                source = nil
            case .planet:
                rows.append(.init("Expect", "A tiny disc at 200 mm; Jupiter's larger moons show as points."))
                source = nil
            default:
                rows.append(.init("Exposure", "On a star tracker, 60–120 s in the suburbs and longer at a dark site. Without one, under about 1.5 s before stars trail."))
                if let h = hours, let n = frames(120) {
                    rows.append(.init("Frames", "Take as many as the time it is up allows: \(h) is about \(n) × 120 s on a tracker."))
                }
                if k == .emission || k == .nebulaUnknown {
                    rows.append(.init("Filter", "A dual-band or light-pollution filter lifts an emission nebula out of a bright sky."))
                }
            }
        default:
            switch k {
            case .moon, .planet, .constellation:
                rows.append(.init("Tip", "Check your instrument's manual for its Moon, planet or wide-field settings."))
            default:
                rows.append(.init("Filter", filterText(k, dualBand: "A dual-band or narrowband filter", broadband: "No filter, or a light-pollution filter only")))
                rows.append(.init("Exposure", "Check your telescope's manual for exposure and gain."))
                if let h = hours { rows.append(.init("Frames", "It is up and clear for \(h) tonight.")) }
            }
        }

        if let v = t.viewable, k != .constellation {
            rows.append(.init("When", "Start at \(Copy.hhmm(v.start, site: site)), when it is clear and high enough; it is best at \(Copy.hhmm(t.peakTime, site: site))."))
        }
        var tip = ShootingTip(title: "How to shoot this with \(presetName == nil ? "your telescope" : "your \(name)")", rows: rows, source: source)
        tip.copyLine = copyNumbers(k, presetID: presetID).map { numbers in
            let what = [t.catalogueID, t.commonName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return "\(what.isEmpty ? t.name : what) · \(presetName ?? name): \(numbers)"
        }
        return tip
    }

    /// The numbers the card gives, without the explanations; nil where it gives none.
    static func copyNumbers(_ k: Kind, presetID: String?) -> String? {
        switch presetID {
        case "dwarf-mini", "dwarf-3":
            switch k {
            case .moon: return "Moon mode, about 1/250 s at gain 0, Astro filter, 20–30 images"
            case .planet, .constellation, .star: return nil
            default:
                let filter = k == .emission ? "Duo-Band" : (k == .broadband ? "Astro" : "Duo-Band or Astro")
                return "\(filter) filter, 15–60 s at gain 60–80, 200–400 frames"
            }
        case "seestar-s50":
            switch k {
            case .emission: return "light-pollution filter on, 10 s frames"
            case .broadband: return "light-pollution filter off, 10 s frames"
            case .nebulaUnknown: return "light-pollution filter on if it glows red, off if not, 10 s frames"
            default: return nil
            }
        case "dslr-apsc-200":
            switch k {
            case .moon, .planet, .star, .constellation: return nil
            case .emission, .nebulaUnknown: return "dual-band or light-pollution filter, 60–120 s on a star tracker, under about 1.5 s without one"
            default: return "60–120 s on a star tracker, under about 1.5 s without one"
            }
        default:
            return nil
        }
    }

    /// "How to shoot this" for an event (v1.0.1). No maker publishes settings for these, so it is guidance without numbers.
    public static func tip(for e: SkyEvent, fov: FieldOfView, presetName: String?, site: Site) -> ShootingTip {
        var rows: [ShootingTip.Row] = []
        switch e.kind {
        case .meteorShower:
            rows.append(.init("Kit", "A telescope's narrow field catches few meteors: use a camera with a wide lens on a tripod."))
            rows.append(.init("Aim", "About 45° from the radiant, high in the darkest part of the sky."))
            rows.append(.init("Exposure", "Shoot continuously, each frame short enough that the stars stay points (the 500 rule), and keep the frames that caught one."))
        case .issPass:
            rows.append(.init("Kit", "Too fast for a smart telescope to follow: photograph it as a streak with a wide lens on a tripod."))
            rows.append(.init("Timing", "Start a long exposure, or a run of short ones, just before it appears at \(Copy.hhmm(e.time, site: site)), and stop as it goes."))
        case .comet:
            rows.append(.init("Filter", filterText(.broadband, dualBand: "A dual-band filter", broadband: "No filter, or a light-pollution filter only")))
            rows.append(.init("Stacking", "It moves against the stars through the night, so keep the stack short, or align the frames on the comet when you stack."))
        case .conjunction:
            rows.append(.init("Framing", e.fits == true ? "Both fit in your field of view: centre the frame between them."
                                              : "Wider than your field of view: use a wider lens, or shoot each on its own."))
        case .lunarEclipse:
            rows.append(.init("Mode", "Start in your telescope's Moon mode. The eclipsed Moon is far dimmer, so lengthen the exposure as it darkens."))
        case .solarEclipse:
            rows.append(.init("Safety", "Never point a telescope or camera at the Sun without a certified solar filter over the front."))
        }
        if let b = e.best, e.kind != .issPass { rows.append(.init("When", "Best at \(Copy.hhmm(b, site: site)).")) }
        // Meteors and the ISS are camera work, so their title does not name the telescope.
        let title = e.kind == .meteorShower || e.kind == .issPass ? "How to shoot this"
                  : "How to shoot this with \(presetName.map { "your \($0)" } ?? "your telescope")"
        return ShootingTip(title: title, rows: rows, source: nil)
    }

    static func filterText(_ k: Kind, dualBand: String, broadband: String) -> String {
        switch k {
        case .emission: "\(dualBand): it passes the hydrogen-alpha and oxygen-III light an emission nebula gives off."
        case .broadband: "\(broadband): this target's light spans the whole spectrum, so a narrow filter would cut most of it."
        default: "\(dualBand) if it glows red (an emission nebula); \(broadband) if it is a reflection or dark nebula."
        }
    }
}
