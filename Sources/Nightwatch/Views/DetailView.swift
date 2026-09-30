import SwiftUI
import SkyCore

/// A target's detail page (v0.6.4, owner-approved mockup): the image fills the window and the text sits on it in black
/// caption boxes. Survey photos fill the page; the Moon, planet photographs and constellation artwork are fitted into the
/// space above the caption so nothing covers them.
struct DetailView: View {
    @EnvironmentObject var store: Store
    let target: RankedTarget
    /// The night the Targets window shows: tonight, or tomorrow night when chosen (owner, 28 September 2026).
    let plan: NightPlan?
    /// The page it was opened from, for the back link ("Eyes and binoculars", not the target's group: owner's UAT).
    var back: String? = nil
    /// Opened from Eyes and binoculars: how to see it, in place of telescope settings until How to shoot this is chosen.
    var eye: EyeView? = nil
    let onBack: () -> Void
    @StateObject private var hero = ThumbnailLoader()
    @StateObject private var tipsUI = TipsState()

    /// Photographs and artwork that must be seen whole; everything else is a survey image to fill the page.
    private var fitted: Bool { target.group == .constellations || target.group == .planets }
    /// A hand-edited config can hold 0.
    private var fov: FieldOfView { FieldOfView(widthDeg: max(0.05, store.config.fov.widthDeg), heightDeg: max(0.05, store.config.fov.heightDeg)) }

    var body: some View {
        DetailPage(back: back ?? target.group.displayName, onBack: onBack) {
            if !fitted {
                Label(showsWholeFieldOfView ? "Shown at your field of view" : "Dashed box = your field of view", systemImage: "viewfinder").captionPill()
            }
        } hero: { pane in
            if fitted {
                fittedHero
            } else {
                // The clear space between the top bar and the caption. The photo is centred on it and overflows it to
                // cover the page; the dashed box stays inside it.
                GeometryReader { f in
                    if let img = hero.image {
                        survey(img, free: f.frame(in: .named("pane")), pane: pane)
                    } else {
                        // Offline with nothing cached: the group's glyph, as the cards show.
                        Image(systemName: Theme.glyph(for: target.group)).font(.system(size: 40)).foregroundStyle(Theme.dim)
                            .frame(width: f.size.width, height: f.size.height)
                    }
                }
            }
        } tips: {
            tipsOverlay
        } title: {
            titleBlock
        } stats: {
            stats
        }
        .task(id: target.id) {
            hero.image = nil; hero.art = nil; hero.imageFovDeg = nil
            if target.group == .constellations { hero.art = ConstellationArt(id: target.id); return }
            // The card's cached image first, so the page is never blank, then a sharp one sized for the window, with more sky
            // around an object bigger than the field of view so the dashed box has room.
            let fovDeg = Thumbnails.fovDeg(for: target, fov: fov)
            hero.image = await Thumbnails.image(for: target, fov: store.config.fov); hero.imageFovDeg = fovDeg
            guard !fitted else { return }
            let context = showsWholeFieldOfView ? 1 : Self.boxContext
            if let big = await Thumbnails.image(for: target, fov: store.config.fov, width: Thumbnails.detailWidth, context: context) {
                hero.image = big; hero.imageFovDeg = fovDeg * context
            }
        }
    }

    /// How much more sky the detail photo shows around an object bigger than the field of view: the box is then at most
    /// 1/1.6 (62.5%) of the photo's width, and 1/(1.6 × 1.5) for an object much bigger than the field.
    static let boxContext = 1.6

    // MARK: Parts

    @ViewBuilder private var fittedHero: some View {
        if let art = hero.art { art }
        else if let img = hero.image { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8)) }
    }

    /// The survey image is fetched at the field of view, or at 1.5 × the object when it is bigger: only then is there a
    /// smaller dashed box to draw.
    private var showsWholeFieldOfView: Bool { Thumbnails.fovDeg(for: target, fov: fov) <= fov.widthDeg + 1e-9 }

    /// The survey photo, centred on the clear space (`free`, in the pane's coordinates) so the target is never under the
    /// caption, drawn large enough to cover the page but never so large that the dashed box leaves the clear space (the box
    /// wins in a very small window).
    @ViewBuilder private func survey(_ img: NSImage, free: CGRect, pane: CGSize) -> some View {
        let aspect = fov.widthDeg / fov.heightDeg
        let dx = abs(free.midX - pane.width / 2), dy = abs(free.midY - pane.height / 2)
        let cover = max(pane.width + 2 * dx, (pane.height + 2 * dy) * aspect)
        // The box's share of the photo's width. None until the wider photo arrives (about 12 s the first time): the card image
        // has no sky to spare, so the box would force it smaller than the page.
        let cardFovDeg = Thumbnails.fovDeg(for: target, fov: fov)
        let k = showsWholeFieldOfView || (hero.imageFovDeg ?? cardFovDeg) <= cardFovDeg + 1e-9 ? 0 : fov.widthDeg / hero.imageFovDeg!
        let drawnW = k > 0 ? min(cover, free.width * 0.94 / k, free.height * 0.94 * aspect / k) : cover
        ZStack {
            Image(nsImage: img).resizable().frame(width: drawnW, height: drawnW / aspect)
            if k > 0 {
                RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: drawnW * k, height: drawnW * k / aspect)
            }
        }
        .frame(width: free.width, height: free.height)   // centred on the clear space; the photo overflows it
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(target.name).font(.system(size: 24, weight: .semibold)).lineLimit(2)
                let on = store.config.favourites.contains(target.id)
                Button { store.config.toggleFavourite(target.id); store.saveConfig() } label: {
                    Image(systemName: on ? "heart.fill" : "heart").font(.system(size: 16, weight: .semibold)).foregroundStyle(on ? Theme.accent : Theme.text)
                }
                .buttonStyle(.plain).help(on ? "Remove from favourites" : "Add to favourites")
                .accessibilityLabel(on ? "Remove from favourites" : "Add to favourites")
            }
            Text(target.subtitle + (target.sizeArcmin.map { String(format: " · %.0f′", $0) } ?? "") + (target.magnitude.map { String(format: " · mag %.1f", $0) } ?? ""))
                .font(.system(size: 13)).foregroundStyle(Theme.text.opacity(0.85))
            Text(String(format: "RA %.2fh · Dec %+.1f°", target.raHours, target.decDeg)).font(.system(size: 11)).foregroundStyle(Theme.dim)
            HStack(spacing: 8) {
                if store.site != nil { HowToShootButton(shown: $tipsUI.shown).help("Filter, exposure and frames for your telescope and this target") }
                planButton.padding(.top, 4)
            }
            // The credit CDS and STScI ask for, on the page that shows their image (ODbL 1.0; STScI non-profit use).
            if !fitted { Text("Image: Digitized Sky Survey – STScI/NASA, Colored & Healpixed by CDS").font(.system(size: 9.5)).foregroundStyle(Theme.dim) }
        }
    }

    /// Tonight's plan from a target's page (#57, redesigned at the owner's UAT): a favourite can be taken off for the night
    /// or put back; any other target up in the clear window can be added for that night only.
    @ViewBuilder private var planButton: some View {
        if let plan, let session = store.session(for: plan), target.viewable != nil, !target.moonWashed {
            let inPlan = session.items.contains { $0.id == target.id }
            let favourite = store.config.favourites.contains(target.id)
            let night = plan.night.key == store.plan?.night.key ? "tonight's plan" : "tomorrow night's plan"
            let label = inPlan ? (favourite ? "Take off \(night)" : "Remove from \(night)") : (favourite ? "Put back in \(night)" : "Add to \(night)")
            Button { store.setInPlan(target.id, !inPlan, night: plan.night.key) } label: {
                Label(label, systemImage: inPlan ? "minus.circle" : "plus.circle")
            }
            .captionButton()
        }
    }

    @ViewBuilder private var stats: some View {
        if let s = store.site, let plan, let w = plan.primary {
            VStack(alignment: .leading, spacing: 8) {
                TileRow(spacing: 6) {
                    StatTile(label: "Best", value: "\(Copy.hhmm(target.peakTime, site: s)) · \(Int(target.peakAltDeg.rounded()))°")
                    StatTile(label: "Above \(Int(store.config.goRule.minAltitudeDeg))°", value: "\(Int(target.visibleFraction * 100))% of window")
                    // The Moon's own page has no separation to give: it says how much of it is lit instead.
                    if target.id == "moon" { StatTile(label: "Illuminated", value: target.typeName.components(separatedBy: " ").first) }
                    else { StatTile(label: "Moon sep.", value: "\(Int(target.moonSepDeg))°") }
                    StatTile(label: "Suggested", value: String(format: "%.0f min stack", min(w.hours, 3) * 60))
                }
                AltitudeChart(target: target, night: plan.night, window: w, minAltitude: store.config.goRule.minAltitudeDeg, site: s)
            }
        }
    }
}

extension DetailView {
    /// The card sits over the bottom of the image area, just above the caption: an overlay takes no layout space, so
    /// opening it never resizes the image, and it is never clipped by the window's bottom edge (owner, 25 Sep 2026).
    @ViewBuilder var tipsOverlay: some View {
        if tipsUI.shown, let s = store.site { tipsCard(site: s) }
        else if let eye, let s = store.site { eyeCard(eye, site: s) }
    }

    /// "How to see this" for a target opened from Eyes and binoculars (owner's UAT, 29 September 2026).
    func eyeCard(_ eye: EyeView, site: Site) -> some View {
        let abbr = target.subtitle.components(separatedBy: " in ").last ?? ""
        let moonUp = plan.flatMap(Planner.moonTonight).map { $0 != .down } ?? false
        let tip = ShootingTips.eyeTip(for: target, eye: eye, constellation: store.constellations.first { $0.id == abbr }?.name,
                                      moonIllumination: plan?.moonIllumination ?? 0, moonUp: moonUp, site: site)
        return ShootingTipCard(tip: tip)
    }

    /// "How to shoot this" (v0.6.7, owner-approved mockup): the settings for the user's own telescope and this kind of
    /// target, sized to tonight's window, with where the numbers come from.
    func tipsCard(site: Site) -> some View {
        let preset = TelescopePresets.shared.first { $0.id == store.config.fovPresetID }
        let tip = ShootingTips.tip(for: target, presetID: preset?.id, presetName: preset?.name,
                                   stackMinutes: target.viewable.map { min($0.hours, 3) * 60 }, site: site)
        return ShootingTipCard(tip: tip)
    }
}

final class TipsState: ObservableObject { @Published var shown = false }

/// The target's altitude from sunset to sunrise: the clear window shaded, the minimum altitude dashed, the curve grey and
/// red only where the target is above the minimum inside the window (as on the Targets cards), a dot at the best moment.
struct AltitudeChart: View {
    let target: RankedTarget
    let night: Night
    let window: ClearWindow
    let minAltitude: Double
    let site: Site

    private var span: TimeInterval { night.sunrise.timeIntervalSince(night.sunset) }
    private func frac(_ t: Date) -> Double { t.timeIntervalSince(night.sunset) / span }

    var body: some View {
        // Every 10 minutes, plus the window's own edges so the red run starts and ends exactly there.
        let times = (stride(from: 0.0, through: 1.0, by: 1.0 / 72).map { night.sunset.addingTimeInterval($0 * span) } + [window.start, window.end])
            .filter { $0 >= night.sunset && $0 <= night.sunrise }.sorted()
        let samples: [(f: Double, t: Date, alt: Double)] = times.map { t in
            (frac(t), t, Ephemeris.altAz(raHours: target.raHours, decDeg: target.decDeg, at: t, site: site).alt)
        }
        VStack(alignment: .leading, spacing: 3) {
            Text("Altitude tonight").font(.system(size: 10)).foregroundStyle(Theme.dim)
            GeometryReader { g in
                let x = { (f: Double) in g.size.width * max(0, min(1, f)) }
                let y = { (alt: Double) in g.size.height * (1 - max(0, min(90, alt)) / 90) }
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: max(0, x(frac(window.end)) - x(frac(window.start))), height: g.size.height)
                    .offset(x: x(frac(window.start)))
                Path { p in p.move(to: CGPoint(x: 0, y: y(minAltitude))); p.addLine(to: CGPoint(x: g.size.width, y: y(minAltitude))) }
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Text("\(Int(minAltitude))°").font(.system(size: 9)).foregroundStyle(Theme.dim).position(x: g.size.width - 10, y: y(minAltitude) - 7)
                Path { p in for (i, s) in samples.enumerated() { let pt = CGPoint(x: x(s.f), y: y(s.alt)); i == 0 ? p.move(to: pt) : p.addLine(to: pt) } }
                    .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                Path { p in
                    var drawing = false
                    for s in samples {
                        guard s.t >= window.start, s.t <= window.end, s.alt >= minAltitude else { drawing = false; continue }
                        let pt = CGPoint(x: x(s.f), y: y(s.alt))
                        if drawing { p.addLine(to: pt) } else { p.move(to: pt); drawing = true }
                    }
                }
                .stroke(Theme.accent, lineWidth: 2.5)
                if target.peakTime >= night.sunset, target.peakTime <= night.sunrise {
                    Circle().fill(Theme.text).frame(width: 6, height: 6).position(x: x(frac(target.peakTime)), y: y(target.peakAltDeg))
                }
            }
            .frame(height: 44)
            HStack {
                Text("Sunset \(Copy.hhmm(night.sunset, site: site))"); Spacer()
                Text("Clear \(Copy.hhmm(window.start, site: site))–\(Copy.hhmm(window.end, site: site))"); Spacer()
                Text("Sunrise \(Copy.hhmm(night.sunrise, site: site))")
            }
            .font(.system(size: 9.5)).foregroundStyle(Theme.dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Altitude tonight. Best \(Copy.hhmm(target.peakTime, site: site)) at \(Int(target.peakAltDeg.rounded())) degrees.")
    }
}

