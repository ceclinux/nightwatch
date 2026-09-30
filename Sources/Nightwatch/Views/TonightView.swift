import SwiftUI
import NightwatchUI
import SkyCore

struct TonightView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    /// The popover's height as laid out, to know when it is taller than the screen (#60).
    @State private var contentHeight: CGFloat = 0
    /// The usable height of the screen the popover is on, not the one with focus (a menu-bar app often has no key window).
    @State private var screenHeight: CGFloat = .greatestFiniteMagnitude

    /// Taller than the screen (a small display, or the Larger Text resolutions): it scrolls rather than losing its footer.
    /// Otherwise exactly as before, with no scroll view at all.
    var body: some View {
        Group {
            if contentHeight > screenHeight {
                ScrollView { content }.frame(height: screenHeight)
            } else {
                content
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Tokens.glassHairline, lineWidth: 1))
        .nightwatchGlass(in: RoundedRectangle(cornerRadius: 13))
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .onAppear { Task { await store.refresh(force: false) } }   // cheap: the 30-minute cache gate decides whether to fetch
        .background(WindowScreenReader { screenHeight = $0 - 24 })
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if store.isAway { awayBar }
            if let plan = store.plan, let site = store.site {
                verdict(plan, site)
                ClearSkyBars(bars: Planner.clearSkyBars(plan: plan, site: site), label: Copy.barsLabel(plan: plan, site: site))
                notice(site)
                tiles(plan, site)
                best(plan, site)
            } else {
                Text(store.lastError ?? "Waiting for the first forecast…").font(.callout).foregroundStyle(Theme.dim).padding(.vertical, 20)
            }
            footer
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 22, trailing: 16))   // extra at the foot: the window otherwise sits tight on the footer row
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    }

    /// One click back to home after "Observe from here" or choosing another site (v0.6.5).
    private var awayBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill").font(.system(size: 10)).foregroundStyle(Tokens.statusWarning).accessibilityHidden(true)
            Text("Observing away from home").font(.system(size: 11))
            Spacer()
            Button("Back to \(store.homeLabel)") { store.goHome() }.buttonStyle(SecondaryButtonStyle())
        }
        .padding(8)
        .background(Tokens.surfaceTile, in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TONIGHT · \(store.site?.name.uppercased() ?? "NO SITE")").font(.system(size: 11)).foregroundStyle(Tokens.textSecondary)
                if let s = store.site, let p = store.plan {
                    Text("\(Copy.dayMonth(p.night.localDate, site: s)) · Bortle \(s.bortle) · EQ tilt \(String(format: "%.1f", abs(s.latitude)))° \(s.latitude >= 0 ? "true north" : "true south")" + (p.mode == .bright ? " · bright night" : ""))
                        .font(.system(size: 11)).foregroundStyle(Tokens.textSecondary)   // wedge angle = site latitude; the vendor app does the alignment
                }
            }
            Spacer()
            Button { open("settings") } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).foregroundStyle(Theme.dim)
                .help("Settings").accessibilityLabel("Settings")
            // A menu-bar app has no menu bar of its own, so Quit lives here (owner, 27 September 2026); ⌘Q works while open.
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.plain).foregroundStyle(Theme.dim)
                .keyboardShortcut("q").help("Quit Nightwatch").accessibilityLabel("Quit Nightwatch")
        }
    }

    /// A menu-bar agent app is never the active app, so a window opened from the popover would land behind
    /// whatever the user is working in. Activate first so the window comes to the front.
    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }

    private func noWindowReason(_ plan: NightPlan, _ site: Site) -> String? {
        Planner.noWindowReasonText(plan: plan, rule: store.config.goRule, bright: store.config.brightNights, site: site)
    }

    private func verdict(_ plan: NightPlan, _ site: Site) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ScoreBezel(score: plan.score,
                       slots: Bezel.slots(darkness: plan.darkSpan, windows: plan.windows, primary: plan.primary, hours: plan.darkHours, site: site),
                       label: Copy.bezelLabel(plan, site: site))
            VStack(alignment: .leading, spacing: 4) {
                if let w = plan.primary {
                    Text(plan.mode == .bright ? "Bright night: Moon and planets" : "Clear window tonight").font(.system(size: 15, weight: .medium))
                    Text("\(Copy.hhmm(w.start, site: site))–\(Copy.hhmm(w.end, site: site)) · \(String(format: "%.1f h", w.hours))").font(.system(size: 13))
                    if plan.mode == .bright {
                        Text(Copy.brightList(plan.brightTargets)).font(.system(size: 10)).foregroundStyle(Tokens.textSecondary)
                    }
                    if let why = Copy.heldBack(plan.limiting) {
                        // No dot: every line under the verdict reads the same way (owner, 28 September 2026).
                        Text(why)
                            .font(.system(size: 10)).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    agreementLine(plan, site)
                } else if !plan.night.hasDarkness && (plan.mode == .dark || !plan.night.hasNauticalDarkness) {
                    Text("No astronomical darkness").font(.system(size: 15, weight: .medium))
                    Text("Too far north or south for this date.").font(.system(size: 10)).foregroundStyle(Tokens.textSecondary)
                } else {
                    Text(store.copy.noWindow).font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    if let why = noWindowReason(plan, site) {
                        Text(why).font(.system(size: 10)).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
                        // For those happy to chance a marginal night: the rule is theirs to loosen (owner's UAT, 30 September 2026).
                        Button("Loosen the go rule in Settings") { open("settings") }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Tokens.controlOn)
                    }
                    // No "Tomorrow" line: after sunrise the popover shows tomorrow night itself (owner, 28 September 2026).
                    agreementLine(plan, site)
                }
            }
        }
    }

    /// Open-Meteo's second opinion (v0.5). When it agrees, a small line with a tick. When it disagrees, one plain grey line
    /// that says what it means ("Less certain: a second forecast sees cloud from 00:00."): no box, no dot, no coloured text
    /// (owner, 28 September 2026).
    @ViewBuilder private func agreementLine(_ plan: NightPlan, _ site: Site) -> some View {
        if let advice = Copy.advice(plan, site: site, alerts: store.config.alerts) {
            Text(advice.line).font(.system(size: 10)).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
        } else if let a = plan.agreement {
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).accessibilityHidden(true)
                Text(Copy.agreementText(a, site: site))
            }
            .font(.system(size: 10)).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// At most one line under the bars: aurora first, then the Clearer sky line (spec §5.1).
    /// The aurora line needs AuroraWatch UK to have published within the hour: its `updated` time moves on every
    /// publication (live: 20:33:32Z then 20:39:31Z, both green), so an older status is stale.
    @ViewBuilder private func notice(_ site: Site) -> some View {
        if let a = store.aurora, store.config.aurora.shows(a), AuroraSettings.isFresh(a, now: Date()) {
            // AuroraWatch UK's terms ask for the source to be named, "ideally with a link or button" to their site.
            Link(destination: URL(string: "https://aurorawatch.lancs.ac.uk/")!) {
                Text("Aurora: \(a.level.rawValue) (AuroraWatch UK) ↗").font(.system(size: 10)).foregroundStyle(Color(hex: a.level.hex))
            }
            .buttonStyle(.plain).help("Open AuroraWatch UK")
        } else if let a = store.bestAway, let w = a.primary {
            Button {
                // The menu-bar label also opens the window on any request; opening a single Window twice is harmless.
                store.targetsRequest = TargetsRequest(section: .darkSites, siteID: a.site.id)
                open("targets")
            } label: {
                Text("Clearer sky \(Geo.format(km: a.site.distanceKm, unit: store.distanceUnit)) \(a.site.compass): \(a.site.name)\(a.site.band.map { " (\($0.displayName))" } ?? ""), clear \(Copy.hhmm(w.start, site: site))–\(Copy.hhmm(w.end, site: site)) →")
                    .font(.system(size: 10)).foregroundStyle(Tokens.textPrimary).multilineTextAlignment(.leading)
            }.buttonStyle(.plain)   // a link, so text.primary: red means clear sky only
        }
    }

    private func tiles(_ plan: NightPlan, _ site: Site) -> some View {
        let dark = plan.darkSpan.map { "\(Copy.hhmm($0.start, site: site))–\(Copy.hhmm($0.end, site: site))" } ?? "None"
        let moon = Planner.moonTonight(plan)
        let pct = "\(Int((plan.moonIllumination * 100).rounded()))%"
        let seeing = plan.darkHours.compactMap(\.seeing)
        let seeingText = seeing.isEmpty ? nil : ["", "<0.5″", "0.5–0.75″", "0.75–1″", "1–1.25″", "1.25–1.5″", "1.5–2″", "2–2.5″", ">2.5″"][min(8, seeing.reduce(0, +) / seeing.count)]
        let wind = plan.darkHours.compactMap(\.windKmh)
        let windText = wind.isEmpty ? nil : String(format: "%.0f km/h", wind.reduce(0, +) / Double(wind.count))
        let dew = Planner.dewRisk(plan.darkHours)
        let frost = plan.darkHours.compactMap(\.tempC).min().map { $0 <= 0 } ?? false
        let transp = plan.darkHours.compactMap(\.transparency)
        let transpText = transp.isEmpty ? nil : (transp.reduce(0, +) / transp.count <= 3 ? "Good" : "Average")
        let moonAt = plan.primary?.midpoint ?? plan.night.darkStart ?? plan.night.sunset
        return VStack(spacing: 8.5) {
            TileRow {
                StatTile(label: "Dark", value: dark)
                MoonTile(value: moon == .down ? "Down tonight" : pct, line: moon.flatMap { $0 == .down ? nil : Copy.moonText($0, site: site) }, at: moonAt)
                StatTile(label: "Seeing", value: seeingText)
            }
            TileRow {
                StatTile(label: "Wind", value: windText)
                StatTile(label: frost ? "Frost likely" : "Dew risk", value: dew?.displayName,
                         hint: dew == .high ? "Dew heater advised" : nil)
                StatTile(label: "Transparency", value: transpText)
            }
        }
    }

    /// Deep-sky picks on a dark night; the Moon and planets on a bright one.
    private func picks(_ plan: NightPlan) -> [RankedTarget] { plan.mode == .bright ? plan.brightTargets : plan.best }

    private func best(_ plan: NightPlan, _ site: Site) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(picks(plan).isEmpty ? "UP TONIGHT" : "BEST TONIGHT").font(.system(size: 10)).foregroundStyle(Tokens.textSecondary)
                Spacer()
                Button("All targets →") { open("targets") }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Open the Targets window: everything up tonight, with timelines, sorting and dark sites")
            }
            if plan.mode == .bright, plan.brightTargets.isEmpty {
                Text("No Moon or planet in a clear window tonight.").font(.system(size: 10)).foregroundStyle(Tokens.textSecondary)
            } else if plan.mode == .dark, plan.best.isEmpty {
                Text("\(plan.targets.count) objects above the horizon during darkness. No clear window, so nothing is recommended.")
                    .font(.system(size: 10)).foregroundStyle(Tokens.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(picks(plan)) { t in
                    VStack(alignment: .leading, spacing: 3) {
                        ThumbnailView(target: t).frame(height: 64).clipShape(RoundedRectangle(cornerRadius: 7))
                        Text(t.catalogueID).font(.system(size: 10.5, weight: .bold)).lineLimit(1).fixedSize(horizontal: false, vertical: true)
                        Text(t.commonName ?? t.typeName).font(.system(size: 10)).foregroundStyle(Tokens.textSecondary).lineLimit(1)
                        Text("Best \(Copy.hhmm(t.peakTime, site: site)) · \(Int(t.peakAltDeg.rounded()))° up").font(.system(size: 8.5, weight: .medium)).foregroundStyle(Tokens.bestLine)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Which service supplied the cloud hours. Apple requires its mark and legal link wherever WeatherKit data is shown: the
    /// mark itself is the link, as on the widgets (owner, 27 September 2026).
    @ViewBuilder private func sourceBadge(_ f: Forecast) -> some View {
        let name = Text(f.cloudSource ?? "Open-Meteo").font(.caption2).foregroundStyle(Theme.dim)
        let badge = Group {
            if let m = f.attributionMarkURL, let url = URL(string: m) {
                AsyncImage(url: url) { $0.resizable().scaledToFit().frame(height: 10) } placeholder: { name }
            } else { name }
        }
        if let l = f.attributionLegalURL, let url = URL(string: l) {
            Link(destination: url) { badge }
                .help("Apple Weather's legal attribution and data sources")
                .accessibilityLabel("Apple Weather, legal attribution and data sources")
        } else { badge }
    }

    /// One centre line, evenly spread as on the large widget: the cloud source, the update time, "Refresh". The notify switch
    /// lives in Settings › Alerts (owner, 27 September 2026).
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let u = store.availableUpdate {
                HStack(spacing: 5) {
                    Circle().fill(Tokens.controlOn).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text("Nightwatch \(u.version) is available").foregroundStyle(Tokens.textPrimary)
                    Link("Download ↗", destination: u.url)
                }
                .font(.system(size: 10.5))
            }
            HStack(alignment: .center, spacing: 0) {
                if let f = store.forecast, let s = store.site {
                    // The mark on the left: its weight looked odd in the middle (owner, 27 September 2026).
                    sourceBadge(f)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        if store.isStale { StaleBadge(fetchedAt: f.fetchedAt) }
                        Text(store.isStale ? store.copy.offlineSince(Copy.hhmm(f.fetchedAt, site: s)) : "Updated \(Copy.hhmm(f.fetchedAt, site: s))")
                            .font(.system(size: 10)).foregroundStyle(Tokens.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    if store.refreshing { ProgressView().controlSize(.small) }
                    Button(store.copy.refresh) { Task { await store.refresh(force: true) } }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Fetch the forecast now and recompute tonight")
                }
            }
        }.padding(.top, 4)
    }
}
