import SwiftUI
import SkyCore
import PhoneCore

extension SkyEventKind {
    var phoneName: String {
        switch self {
        case .meteorShower: "Meteor shower"
        case .lunarEclipse: "Lunar eclipse"
        case .solarEclipse: "Solar eclipse"
        case .conjunction: "Conjunction"
        case .comet: "Comet"
        case .issPass: "Space station"
        case .occultation: "Occultation"
        }
    }
    var phoneSymbol: String {
        switch self {
        case .meteorShower: "sparkles"
        case .lunarEclipse: "moon.fill"
        case .solarEclipse: "sun.max.fill"
        case .conjunction: "circle.dotted"
        case .comet: "sparkle"
        case .issPass: "dot.radiowaves.left.and.right"
        case .occultation: "moonphase.waxing.crescent"
        }
    }
}

/// An event's chips, shared by its card and its page: At peak, Fits frame or Too wide, Clear or Cloudy, and the horizon warnings.
struct EventChips: View {
    let event: SkyEvent
    var onPage = false
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            if event.atPeak { Chip(text: "At peak", symbol: "sparkle") }
            if let f = event.fits { Chip(text: f ? "Fits frame" : "Too wide", symbol: "viewfinder") }
            if let c = event.clear { Chip(text: onPage ? (c ? "Clear then" : "Cloudy then") : (c ? "Clear" : "Cloudy"), symbol: c ? "checkmark" : "cloud.fill", warning: !c) }
            if event.behindHorizon {
                Chip(text: event.kind == .meteorShower ? "Radiant behind your horizon" : "Behind your horizon", symbol: "eye.slash", warning: true)
            }
            if onPage, let o = event.occultation, o.moonIllumination >= 0.7 {
                Chip(text: "Bright Moon, \(Int((o.moonIllumination * 100).rounded()))% lit", symbol: "moon.fill", warning: true)
            }
        }
    }
}

struct EventCard: View {
    let event: SkyEvent
    let site: Site
    /// Say the day as well as the time: for an event that is not tonight's.
    var withDate = false
    @Environment(\.phoneTheme) private var theme

    private var when: String {
        guard withDate else { return Copy.hhmm(event.when, site: site) }
        let f = DateFormatter(); f.timeZone = site.timeZone; f.locale = Locale(identifier: "en_GB"); let sameYear = site.calendar.component(.year, from: event.when) == site.calendar.component(.year, from: .now)
        f.dateFormat = sameYear ? "EEE d MMM HH:mm" : "EEE d MMM yyyy HH:mm"
        return f.string(from: event.when)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.phoneSymbol).font(.title3).foregroundStyle(theme.accent)
                .frame(width: 52, height: 52).background(theme.tile, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title.plainDashes).font(.headline.weight(.heavy)).lineLimit(2)
                Text(event.detail.plainDashes).font(.footnote).secondary().lineLimit(3)
                Text("\(event.kind.phoneName) · \(when)").font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(theme.bestLine)
                EventChips(event: event).padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote).secondary().padding(.top, 4)
        }
        .padding(10)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

/// Tonight's events, then what is coming up (the Moon covering a star or planet over the year ahead).
struct EventsScreen: View {
    @ObservedObject var store: PhoneStore
    @State private var sort = EventSort.time
    @State private var query = ""
    // `-demoOpen event` opens the first event's page at launch (or `-demoEventKind comet`, for one of that kind), for screenshots.
    @State private var demoEvent = UserDefaults.standard.string(forKey: "demoOpen") == "event"
    @Environment(\.phoneTheme) private var theme

    private var demoPick: SkyEvent? {
        let kind = UserDefaults.standard.string(forKey: "demoEventKind")
        return store.events.first { kind == nil || $0.kind.rawValue == kind }
    }

    private func matches(_ e: SkyEvent) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || [e.title, e.detail, e.kind.phoneName].contains { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let tonight = Events.sorted(store.events.filter(matches), by: sort)
        let tonightIDs = Set(store.events.map(\.id))
        let ahead = store.occultationsAhead.filter { !tonightIDs.contains($0.id) && $0.time > store.now && matches($0) }.sorted { $0.when < $1.when }.prefix(12)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let site = store.site {
                    Menu { Picker("Sort", selection: $sort) { ForEach(EventSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: {
                        Label("Sort: \(sort.rawValue)", systemImage: "arrow.up.arrow.down").font(.callout)
                    }
                    if tonight.isEmpty {
                        Text(query.isEmpty ? "Nothing special tonight: no shower at its peak, no bright comet, no space station pass, no planets close together." : "No match.")
                            .font(.callout).secondary().padding(.vertical, 12)
                    }
                    ForEach(Array(tonight.enumerated()), id: \.element.id) { i, e in
                        NavigationLink { EventDetailScreen(store: store, event: e) } label: { EventCard(event: e, site: site) }.buttonStyle(PressStyle()).risesIn(i)
                    }
                    if !ahead.isEmpty {
                        Text("COMING UP FROM \(site.name.uppercased())").capsLabel().padding(.top, 12)
                        Text(SettingsCopy.comingUpCaption).font(.caption).secondary()
                        ForEach(Array(ahead), id: \.id) { e in
                            NavigationLink { EventDetailScreen(store: store, event: e) } label: { EventCard(event: e, site: site, withDate: true) }.buttonStyle(PressStyle())
                        }
                    }
                }
            }
            .padding(16).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { StarField(seed: "events", calm: true).ignoresSafeArea() }
        .searchable(text: $query, prompt: "Perseids, eclipse, Moon")
        .navigationTitle("Events")
        .navigationBarTitleDisplayModeInline()
        .navigationDestination(isPresented: $demoEvent) { if let e = demoPick { EventDetailScreen(store: store, event: e) } }
    }
}

struct EventDetailScreen: View {
    @ObservedObject var store: PhoneStore
    let event: SkyEvent
    @State private var calendarFile: URL?
    @Environment(\.phoneTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title.plainDashes).font(.title2.weight(.semibold))
                    Text(event.detail.plainDashes).font(.callout).secondary().fixedSize(horizontal: false, vertical: true)
                    EventChips(event: event, onPage: true).padding(.top, 2)
                }
                if !event.facts.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(event.facts, id: \.label) { f in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(f.label).font(.caption).secondary().frame(width: 96, alignment: .leading)
                                    Text(f.value.plainDashes).font(.footnote).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                if let site = store.site {
                    let preset = (try? TelescopePresets.bundled())?.first { $0.id == store.config.fovPresetID }
                    ShootingTipCard(tip: ShootingTips.tip(for: event, fov: store.config.fov, presetName: preset?.name, site: site))
                    if let calendarFile {
                        ShareLink(item: calendarFile) { Label("Add to Calendar", systemImage: "calendar.badge.plus").font(.body.weight(.medium)) }
                            .padding(.top, 2)
                    }
                }
            }
            .padding(16).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background { StarField(seed: event.id, calm: true).ignoresSafeArea() }
        .navigationTitle(event.kind.phoneName)
        .navigationBarTitleDisplayModeInline()
        .onAppear(perform: prepareCalendar)
    }

    @ViewBuilder private var hero: some View {
        if event.kind == .issPass, !event.path.isEmpty, let site = store.site {
            SkyPathChart(path: event.path, site: site).frame(height: 300)
        } else if event.kind == .meteorShower, let id = event.radiantConstellation, let data = bundledArt("\(id)-figure", folder: "Constellations"),
                  let img = Image(platformData: data) {
            img.resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 240).opacity(theme.isRed ? 0.7 : 1).accessibilityHidden(true)
        } else {
            Image(systemName: event.kind.phoneSymbol).font(.system(size: 54)).foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity, minHeight: 130).background(theme.tile, in: RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
        }
    }

    private func prepareCalendar() {
        guard calendarFile == nil, let site = store.site else { return }
        let name = event.title.replacingOccurrences(of: "/", with: "-").plainDashes
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).ics")
        if (try? CalendarFile.ics(for: event, site: site).write(to: url, atomically: true, encoding: .utf8)) != nil { calendarFile = url }
    }
}

/// A space station pass drawn on the sky, as the Mac draws it: the horizon as a circle with the compass points, the zenith at the
/// centre, and the pass from where it appears, through its highest point, to where it goes (north up, east to the left).
struct SkyPathChart: View {
    let path: [SkyPathPoint]
    let site: Site
    @Environment(\.phoneTheme) private var theme

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = max(40, min(size.width, size.height) / 2 - 56)
            func pt(_ p: SkyPathPoint) -> CGPoint { let o = p.chartOffset(radius: Double(r)); return CGPoint(x: c.x + o.dx, y: c.y + o.dy) }
            func out(_ q: CGPoint, _ by: CGFloat) -> CGPoint {
                let dx = q.x - c.x, dy = q.y - c.y, len = max(1, (dx * dx + dy * dy).squareRoot())
                return CGPoint(x: q.x + dx / len * by, y: q.y + dy / len * by)
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(theme.textSecondary.opacity(0.6)), lineWidth: 1)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r / 2, y: c.y - r / 2, width: r, height: r)), with: .color(theme.textSecondary.opacity(0.25)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            for (label, az) in [("N", 0.0), ("E", 90), ("S", 180), ("W", 270)] {
                let p = out(pt(SkyPathPoint(label: label, time: .now, azimuthDeg: az, altitudeDeg: 0)), 12)
                ctx.draw(Text(label).font(.caption.weight(.semibold)).foregroundStyle(theme.textSecondary), at: p)
            }
            let pts = path.map(pt)
            guard pts.count >= 2, let a = pts.first, let b = pts.last else { return }
            var line = Path(); line.move(to: a)
            if pts.count == 3 {
                let m = pts[1]   // a curve through the highest point: its control point sits beyond it
                line.addQuadCurve(to: b, control: CGPoint(x: 2 * m.x - (a.x + b.x) / 2, y: 2 * m.y - (a.y + b.y) / 2))
            } else { line.addLine(to: b) }
            ctx.stroke(line, with: .color(theme.accent), lineWidth: 2.5)
            for (i, q) in pts.enumerated() {
                let last = i == pts.count - 1, mid = pts.count == 3 && i == 1
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 3.5, y: q.y - 3.5, width: 7, height: 7)), with: .color(last ? theme.accent : theme.textPrimary))
                let text = Text("\(path[i].label) \(Copy.hhmm(path[i].time, site: site))").font(.caption2).monospacedDigit().foregroundStyle(theme.textPrimary)
                ctx.draw(text, at: mid ? CGPoint(x: q.x, y: q.y - 14) : out(q, 30))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(path.map { "\($0.label) \(Copy.hhmm($0.time, site: site)), \(Geo.compass($0.azimuthDeg)), \(Int($0.altitudeDeg.rounded())) degrees up" }.joined(separator: "; "))
    }
}
