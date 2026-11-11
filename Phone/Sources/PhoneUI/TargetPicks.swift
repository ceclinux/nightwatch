import SwiftUI
import SkyCore
import PhoneCore

/// The SF Symbol for a target group, as on the Mac (its `TargetGroup.symbolName` lives in the Mac-only `NightwatchUI`).
extension TargetGroup {
    var phoneSymbol: String {
        switch self {
        case .nebulae: "cloud.fill"
        case .galaxies: "hurricane"
        case .clusters: "sparkles"
        case .stars: "star.fill"
        case .planets: "circle.circle"
        case .events: "calendar"
        case .constellations: "point.3.connected.trianglepath.dotted"
        }
    }
}

/// A DSS2 survey cutout for a target, from disk when it is there and from CDS when it is not and the connection allows it.
/// Kept per object and field of view, as the Mac keeps them, and dropped when not shown for 30 days.
@MainActor
final class SurveyLoader: ObservableObject {
    @Published var data: Data?

    func load(url: URL, cacheName: String, allowDownload: Bool, folder: String = "thumbs", timeout: TimeInterval = 20) async {
        let dir = ImageCache.directory(folder)
        let file = dir.appendingPathComponent(cacheName)
        if let cached = ImageCache.load(file) {
            data = cached
            if ThumbnailFiles.needsTouch(modified: (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date, now: .now) {
                try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path)
            }
            return
        }
        guard allowDownload else { return }
        guard let bytes = await SurveyFetch.shared.image(url, timeout: timeout), Image(platformData: bytes) != nil else { return }
        ImageCache.save(bytes, to: file)
        Self.pruneStale(in: dir)
        data = bytes
    }

    private static func pruneStale(in dir: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        var modified: [String: Date] = [:]
        for n in names { modified[n] = (try? fm.attributesOfItem(atPath: dir.appendingPathComponent(n).path))?[.modificationDate] as? Date }
        for n in ThumbnailFiles.staleImages(names: names, modified: modified, now: .now) { try? fm.removeItem(at: dir.appendingPathComponent(n)) }
    }
}

/// A heic from the app's bundled artwork folders (the owner's constellation and Milky Way art, copied from the Mac app).
func bundledArt(_ name: String, folder: String) -> Data? {
    Bundle.main.url(forResource: name, withExtension: "heic", subdirectory: folder).flatMap { try? Data(contentsOf: $0) }
}

/// A target's picture on the same dark tile the Mac uses, chosen by `TargetPick.picture`. Photographs, and only photographs,
/// are drawn in one red hue in red mode.
struct TargetPicture: View {
    let pick: TargetPick
    /// A target's own page asks for the sharp picture too, laid over the card photo when it arrives (cheap connections only).
    var sharp: (url: URL, cacheName: String)? = nil
    @StateObject private var survey = SurveyLoader()
    @StateObject private var sharpLoader = SurveyLoader()
    @StateObject private var moon = MoonLoader()
    @Environment(\.phoneTheme) private var theme
    @Environment(\.allowsOptionalDownloads) private var allowsDownloads

    /// `lift` brightens a survey cutout a little so a near-empty field (an open cluster, a faint galaxy) still shows against the glass.
    private func photo(_ data: Data, fill: Bool = true, lift: Bool = false) -> some View {
        Group {
            if let img = Image(platformData: data) {
                img.resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                    .contrast(lift ? 1.15 : 1).brightness(lift ? 0.1 : 0)
                    .saturation(theme.isRed ? 0 : 1).colorMultiply(theme.isRed ? Color(hex: 0xC0180E) : .white)
            }
        }
    }

    var body: some View {
        ZStack {
            Color(hex: 0x0E1018)
            switch pick.picture {
            case .survey(let url, let name):
                if let d = survey.data { Color.clear.overlay(photo(d, lift: true)).transition(.opacity) } else { symbol }
                Color.clear.task(id: name) { await survey.load(url: url, cacheName: name, allowDownload: allowsDownloads) }
                if let d = sharpLoader.data { Color.clear.overlay(photo(d, lift: true)).transition(.opacity) }
                if let sharp {
                    Color.clear.task(id: sharp.cacheName) {
                        await sharpLoader.load(url: sharp.url, cacheName: sharp.cacheName, allowDownload: allowsDownloads, folder: "sharp", timeout: TargetPick.sharpTimeout)
                    }
                }
            case .moon(let at):
                if let d = moon.data { Color.clear.overlay(photo(d)).transition(.opacity) } else { symbol }
                Color.clear.task(id: MoonImage.hourKey(for: at)) { await moon.load(at: at, allowDownload: allowsDownloads) }
            case .planet(let name):
                if let p = Planet(rawValue: name), let u = PlanetImages.url(for: p), let d = try? Data(contentsOf: u) { Color.clear.overlay(photo(d)) } else { symbol }
            case .constellation(let id):
                if let f = bundledArt("\(id)-figure", folder: "Constellations"), let p = bundledArt("\(id)-plot", folder: "Constellations") {
                    ZStack { art(f); art(p) }.padding(4)
                } else { symbol }
            case .milkyWay(let id):
                if let d = bundledArt(id, folder: "Events") { art(d).padding(4) } else { symbol }
            case .symbol:
                symbol
            }
        }
        .animation(.easeOut(duration: 0.3), value: survey.data != nil || moon.data != nil || sharpLoader.data != nil)
        .accessibilityHidden(true)
    }

    private func art(_ data: Data) -> some View {
        Group { if let img = Image(platformData: data) { img.resizable().aspectRatio(contentMode: .fit).opacity(theme.isRed ? 0.7 : 1)
            .saturation(theme.isRed ? 0 : 1).colorMultiply(theme.isRed ? Color(hex: 0xC0180E) : .white) } }
    }

    private var symbol: some View {
        Image(systemName: pick.group.phoneSymbol).font(.title2).foregroundStyle(theme.textSecondary)
    }
}

/// "BEST TONIGHT": three glass cards, a picture over the catalogue ID, the name, and when it is highest. `row` is side by side (iPad);
/// `list` is a card a line (iPhone), with the picture beside the words. `fills` lets the row take the height the page has left, so a
/// tall iPad screen has no empty foot.
struct PicksSection: View {
    enum Style { case row, list }
    let model: TonightModel
    var pictureHeight: CGFloat = 78
    var style: Style = .row
    var fills = false
    @Environment(\.phoneTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.allowsOptionalDownloads) private var allowsDownloads

    private var needsPhotos: Bool { model.picks.contains { if case .survey = $0.picture { true } else { false } } }

    /// A target's three lines: the name heavy, what it is in wide-tracked capitals, and when it is highest. One place, so the photo card and
    /// the solid card at accessibility sizes say it the same way.
    private func words(_ p: TargetPick, name: Color? = nil, line: Color? = nil, best: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(p.title).font(.title2.weight(.heavy)).foregroundStyle(name ?? theme.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
            Text(p.line.uppercased()).font(.caption2.weight(.regular)).tracking(1.4).foregroundStyle(line ?? theme.textSecondary).lineLimit(1)
            Text(p.best).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(best ?? theme.bestLine).lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    /// The picture runs to the card's edges with the words over a dark foot; the "best" line is the card's one warm-white note.
    private func photoCard(_ p: TargetPick, minHeight: CGFloat, fills: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            TargetPicture(pick: p)
            LinearGradient(colors: [.clear, Color.black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            words(p, name: Color(hex: 0xF4F1EA), line: Color(hex: 0xC9D2EA), best: theme.lit)
            .padding(14)
        }
        .frame(minHeight: minHeight, maxHeight: fills ? .infinity : minHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LinearGradient(colors: [theme.glassHairline.opacity(2.2), theme.glassHairline], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }

    /// At the accessibility text sizes the words leave the picture: a solid card, picture above, words beneath.
    private func solidCard(_ p: TargetPick) -> some View {
        Card(padding: 8) {
            VStack(alignment: .leading, spacing: 8) {
                TargetPicture(pick: p).frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10))
                words(p).padding(.horizontal, 4).padding(.bottom, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.picksHeading).capsLabel()
            if let note = model.picksNote { Text(note).font(.footnote).secondary().fixedSize(horizontal: false, vertical: true) }
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) { ForEach(model.picks) { solidCard($0) } }
            } else if style == .list {
                VStack(spacing: 12) { ForEach(model.picks) { photoCard($0, minHeight: 132, fills: false) } }
            } else {
                HStack(alignment: .top, spacing: 14) { ForEach(model.picks) { photoCard($0, minHeight: pictureHeight + 60, fills: fills) } }
                    .frame(maxHeight: fills ? .infinity : nil)
            }
            if needsPhotos && !allowsDownloads {
                Text("Target photos load only on a connection without data limits.").font(.caption2).secondary()
            }
        }
        .frame(maxHeight: fills ? .infinity : nil, alignment: .top)
    }
}
