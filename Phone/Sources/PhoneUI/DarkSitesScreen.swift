import SwiftUI
import MapKit
import SkyCore
import PhoneCore

/// Dark sites within the radius of where you observe, with tonight's score and clear window at the nearest eight, as the Mac lists them.
struct DarkSitesScreen: View {
    @ObservedObject var store: PhoneStore
    @AppStorage("darkSiteSort") private var sortRaw = SiteSort.score.rawValue
    @Environment(\.phoneTheme) private var theme

    var body: some View {
        let nearest = SiteComparison.nearestClear(store.sitePlans)
        let radius = Geo.format(km: store.config.darkSites.radiusKm, unit: store.distanceUnit)
        // With nothing clear tonight "Nearest clear" has nothing to put first, so the choice is not offered.
        let sort = nearest == nil ? SiteSort.score : (SiteSort(rawValue: sortRaw) ?? .score)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Within \(radius) of \(store.site?.name ?? "here") · \(sort == .score ? "sorted by tonight's score" : "nearest clear sky first")")
                    .font(.footnote).secondary()
                if store.isAway { Button("Back to \(store.homeLabel)") { Haptic.selection(); store.goHome() }.buttonStyle(PressStyle()).font(.callout.weight(.medium)).foregroundStyle(theme.accent) }
                if nearest != nil {
                    PhoneSegmented(selection: Binding(get: { sort }, set: { sortRaw = $0.rawValue }),
                                   options: SiteSort.allCases.map { ($0.rawValue, $0) })
                }
                if let n = nearest, let w = n.primary, let here = store.site {
                    Text("Nearest clear sky: \(n.site.name), \(Geo.format(km: n.site.distanceKm, unit: store.distanceUnit)) \(n.site.compass), clear \(Copy.hhmm(w.start, site: here)) to \(Copy.hhmm(w.end, site: here))")
                        .font(.callout.weight(.medium))
                } else if store.sitePlans.contains(where: { !$0.forecastMissing }) {
                    Text("No site within \(radius) has a clear window tonight.").font(.callout).secondary()
                }
                if store.darkSitesSkipped {
                    Text("Forecasts and place names for these sites wait for a cheaper connection (Wi-Fi, or cellular without Low Data Mode).").font(.footnote).secondary()
                }
                if !store.config.darkSites.enabled {
                    EmptyState(title: "Dark sites are off", message: "Turn them on in Settings, Dark sites.")
                } else if store.darkSitesWorking && store.darkSites.isEmpty {
                    ShimmerText(text: "Looking for dark sites near \(store.site?.name ?? "you")").padding(.vertical, 20)
                } else if store.darkSites.isEmpty {
                    EmptyState(title: "No dark sites in range", message: "None within \(radius). Widen the radius in Settings.")
                }
                ForEach(Array(SiteComparison.sorted(store.sitePlans, by: sort).enumerated()), id: \.element.id) { i, p in
                    DarkSiteCard(store: store, plan: p, nearestClear: p.id == nearest?.id).risesIn(i)
                }
                ForEach(store.darkSites.dropFirst(3)) { DarkSiteCard(store: store, plan: SitePlan.missing($0)) }
            }
            .padding(16).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background { StarField(seed: "dark-sites", calm: true).ignoresSafeArea() }
        .onAppear { store.darkSitesPage(open: true) }
        .onDisappear { store.darkSitesPage(open: false) }
        .navigationTitle("Dark sites")
        .navigationBarTitleDisplayModeInline()
    }
}

struct DarkSiteCard: View {
    @ObservedObject var store: PhoneStore
    let plan: SitePlan
    var nearestClear = false
    @Environment(\.phoneTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let s = plan.site
        VStack(alignment: .leading, spacing: 8) {
            SiteMapPicture(site: s).frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) { if nearestClear { Chip(text: "Nearest clear sky", symbol: "mappin.and.ellipse").padding(6) } }
            HStack(alignment: .firstTextBaseline) {
                Text(s.name.plainDashes).font(.headline.weight(.heavy)).lineLimit(2)
                Spacer()
                if !plan.forecastMissing { Text("\(plan.score)").font(.title2.weight(.heavy)).monospacedDigit().foregroundStyle(plan.qualifies ? theme.accent : theme.textSecondary) }
            }
            Text("\(Geo.format(km: s.distanceKm, unit: store.distanceUnit)) \(s.compass) · \(s.kind.capitalized)" +
                 (s.bortle.map { " · Bortle \($0)" } ?? s.band.map { " · \($0.displayName)" } ?? "")).font(.caption).secondary()
            // Compared with home, not with whichever site is in view: while away, "at home" would be the wrong place.
            if let home = store.homeSite {
                let sky = s.bortle.map { "Bortle \($0)" } ?? s.band?.displayName ?? "darkness unknown"
                let atHome = store.isAway ? "at \(store.homeLabel) (home)" : "at home"
                if !plan.forecastMissing, let hp = store.homePlan {
                    Text("Score \(plan.score) vs \(hp.score) \(atHome) · \(sky), home Bortle \(home.bortle)").font(.caption)
                        .foregroundStyle(plan.score >= hp.score + 20 ? theme.accent : theme.textSecondary)
                } else {
                    Text("\(sky), home Bortle \(home.bortle)").font(.caption).secondary()
                }
            }
            if s.isComputed { Text("Found from light-pollution data: check access and park considerately.").font(.caption).secondary() }
            if let w = plan.primary, let here = store.site {
                Text("Clear \(Copy.hhmm(w.start, site: here)) to \(Copy.hhmm(w.end, site: here)) · \(String(format: "%.1f h", w.hours))").font(.caption.weight(.medium)).monospacedDigit()
            } else if plan.forecastMissing {
                Text("No forecast fetched (beyond the nearest three, or offline)").font(.caption).secondary()
            } else {
                Text("No clear window tonight.").font(.caption).secondary()
            }
            actions(s)
        }
        .padding(12)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }

    private func actions(_ s: DarkSite) -> some View {
        let maps = Button { Haptic.selection(); openMaps(s) } label: { Label("Open in Maps", systemImage: "map").lineLimit(1) }
            .buttonStyle(PressStyle()).font(.callout.weight(.medium)).foregroundStyle(theme.accent).frame(minHeight: 44)
        let observe = Button { Haptic.impact(.medium); store.visit(s) } label: { Text("Observe from here").lineLimit(1) }
            .buttonStyle(PressStyle()).font(.callout.weight(.heavy)).foregroundStyle(theme.ember).frame(minHeight: 44)
        let source = Group { if let src = s.source, let url = URL(string: src) { Link("Source", destination: url).font(.caption) } }
        // Side by side when they fit; one above the other, flush right, when the width or the text size says they do not.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { source; Spacer(minLength: 0); maps; observe }
            VStack(alignment: .trailing, spacing: 0) { observe; maps; source }.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Apple Maps at the site, pinned and labelled with its name. A plain maps.apple.com link, which iOS and iPadOS both hand to Maps
    /// (the MKMapItem call did nothing on the iPad).
    private func openMaps(_ s: DarkSite) {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "ll", value: "\(s.coordinate.latitude),\(s.coordinate.longitude)"), URLQueryItem(name: "q", value: s.name)]
        if let url = c.url { openURL(url) }
    }
}

/// A small map of the site, about 5 km across, drawn once and kept (the Mac keeps one too). Fetched only on a cheap connection.
struct SiteMapPicture: View {
    let site: DarkSite
    @State private var image: Image?
    @Environment(\.phoneTheme) private var theme
    @Environment(\.allowsOptionalDownloads) private var allowsDownloads

    var body: some View {
        ZStack {
            Rectangle().fill(theme.tile)
            if let image {
                image.resizable().aspectRatio(contentMode: .fill)
                    .saturation(theme.isRed ? 0 : 1).colorMultiply(theme.isRed ? Color(hex: 0xC0180E) : .white)
                Circle().fill(theme.ember).frame(width: 12, height: 12).overlay(Circle().stroke(Color.white, lineWidth: 2))
            } else {
                Image(systemName: "map").font(.title2).foregroundStyle(theme.textSecondary)
            }
        }
        .accessibilityHidden(true)
        .task(id: site.id) { image = await SiteMaps.image(for: site, allowDownload: allowsDownloads) }
    }
}

enum SiteMaps {
    static let widthMetres = 5000.0, size = CGSize(width: 560, height: 220)
    private static var dir: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("maps", isDirectory: true) }

    static func image(for s: DarkSite, allowDownload: Bool) async -> Image? {
        let file = dir.appendingPathComponent("map-\(s.id).jpg")
        if let data = try? Data(contentsOf: file), let img = Image(platformData: data) { return img }
        guard allowDownload else { return nil }
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: s.coordinate.latitude, longitude: s.coordinate.longitude),
                                      latitudinalMeters: widthMetres * size.height / size.width, longitudinalMeters: widthMetres)
        o.size = size
        #if canImport(UIKit)
        o.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        guard let snap = try? await MKMapSnapshotter(options: o).start(), let jpg = snap.image.jpegData(compressionQuality: 0.8) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? jpg.write(to: file, options: .atomic)
        return Image(platformData: jpg)
        #else
        return nil
        #endif
    }
}

/// Under Tonight's header: while observing from a dark site that is not saved, say so, with Keep and Back; and when a site within
/// the radius has a much better night, say where (the Mac popover's "Clearer sky" line).
struct VisitBar: View {
    @ObservedObject var store: PhoneStore
    @Environment(\.phoneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let v = store.visitingSite {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Observing from \(v.name.plainDashes)").font(.callout.weight(.medium))
                        HStack(spacing: 18) {
                            if store.config.canAddSite { Button("Keep this site") { Haptic.success(); store.keepVisiting() }.buttonStyle(PressStyle()) }
                            Button("Back to \(store.homeLabel)") { Haptic.selection(); store.goHome() }.buttonStyle(PressStyle())
                        }
                        .font(.callout.weight(.semibold)).foregroundStyle(theme.accent).frame(minHeight: 44, alignment: .leading)
                    }
                }
            } else if store.isAway {
                Button("Back to \(store.homeLabel)") { Haptic.selection(); store.goHome() }.font(.callout.weight(.semibold)).foregroundStyle(theme.accent).frame(minHeight: 44)
            }
            if let b = store.bestAway, let w = b.primary, let here = store.site {
                NavigationLink { DarkSitesScreen(store: store) } label: {
                    Text("Clearer sky at \(b.site.name.plainDashes), \(Geo.format(km: b.site.distanceKm, unit: store.distanceUnit)) \(b.site.compass): score \(b.score), clear \(Copy.hhmm(w.start, site: here)) to \(Copy.hhmm(w.end, site: here))")
                        .font(.footnote.weight(.medium)).foregroundStyle(theme.textPrimary).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}
