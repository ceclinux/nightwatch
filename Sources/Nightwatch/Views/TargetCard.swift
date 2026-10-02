import SwiftUI
import NightwatchUI
import SkyCore

/// The Targets window's card (v1.0.1), shared by targets and events so the two cannot drift apart: a picture with chips in
/// its top-right corner and an optional badge (the favourite heart) top-left, a title row, and a footer (the timeline).
/// Controls stay inside the card: an overlay outside its Liquid Glass view is drawn under the glass.
struct TargetCardFrame<Picture: View, Corner: View, Badge: View, Footer: View>: View {
    var dimmed = false
    /// In Tonight's plan (#57): outlined in the accent.
    var highlighted = false
    let title: String
    /// Beside the title, dimmer: a target's Caldwell number.
    var note: String? = nil
    /// The second line, the name people know (owner, 28 September 2026); empty for an event, whose title is its name.
    let subtitle: String
    /// Right of the title: a magnitude or an event's time; nil shows nothing, never a placeholder such as "mag –".
    let trailing: String?
    @ViewBuilder let picture: () -> Picture
    @ViewBuilder let corner: () -> Corner
    @ViewBuilder let badge: () -> Badge
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            picture().frame(height: 110).overlay(alignment: .topTrailing) { corner().padding(8) }
                .opacity(dimmed ? 0.45 : 1)
                .overlay(alignment: .topLeading) { badge().padding(8) }   // after the dimming, so a greyed favourite's heart stays bright
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    // Priority rather than a fixed size: an event's title can be long ("Partial solar eclipse from …").
                    Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Tokens.textPrimary).lineLimit(1).truncationMode(.tail).layoutPriority(1)
                    if let note { Text(note).font(.system(size: 11.5)).foregroundStyle(Tokens.textSecondary).lineLimit(1) }
                    Spacer(minLength: 4)
                    if let trailing { Text(trailing).font(.system(size: 9)).foregroundStyle(Tokens.textSecondary).fixedSize() }
                }
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Tokens.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            footer()
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(highlighted ? Tokens.accentClear : Tokens.cardOutline, lineWidth: 1))
        .nightwatchGlass(in: RoundedRectangle(cornerRadius: 9), fill: Tokens.targetsCard)
    }
}

/// A plain button on a page's caption: "How to shoot this", "Add to tonight's plan".
extension View {
    func captionButton() -> some View {
        buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The owner's event artwork (v1.0.1), bundled as Resources/Events/<name>.heic by scripts/import-event-art.sh.
struct EventArt: View {
    let image: NSImage?

    init(name: String) {
        image = Bundle.main.url(forResource: name, withExtension: "heic", subdirectory: "Events").flatMap(NSImage.init(contentsOf:))
    }
    init(kind: SkyEventKind) { self.init(name: EventArt.name(kind)) }

    static func name(_ kind: SkyEventKind) -> String {
        switch kind {
        case .meteorShower: "meteor-showers"
        case .comet: "comets"
        case .conjunction: "conjunctions"
        case .issPass: "iss"
        case .solarEclipse: "solar-eclipse"
        case .lunarEclipse: "lunar-eclipse"
        case .occultation: "occultation"   // no artwork yet: EventPicture draws one
        }
    }

    var body: some View {
        if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).accessibilityHidden(true) }
        else { Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.dim).accessibilityHidden(true) }
    }
}

/// An event card's picture: the artwork on the same dark tile a target's thumbnail sits on.
struct EventPicture: View {
    let kind: SkyEventKind
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.055, green: 0.063, blue: 0.094))
            if kind == .occultation { OccultationGlyph().padding(10) } else { EventArt(kind: kind).padding(4) }
        }
    }
}

/// An occultation card's picture (#115): the Moon with stars at its edge, one about to go behind it.
struct OccultationGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) * 0.36, c = CGPoint(x: size.width * 0.55, y: size.height / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.85, green: 0.83, blue: 0.78)))
            for (dx, dy, s) in [(-1.25, -0.45, 3.0), (-1.55, 0.2, 2.6), (-1.0, 0.75, 2.4), (1.35, 0.15, 2.4)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x + dx * r - s, y: c.y + dy * r - s, width: 2 * s, height: 2 * s)), with: .color(.white))
            }
        }
        .accessibilityHidden(true)
    }
}

/// An ISS pass drawn on the sky (v1.0.1, owner's choice): the horizon as a circle with the compass points, the zenith at
/// the centre, and the pass from where it appears, through its highest visible point, to where it goes. The projection is
/// `SkyPathPoint.chartOffset` (north up, east to the left, as the sky looks lying on your back with your head north).
struct SkyPathView: View {
    let path: [SkyPathPoint]
    let site: Site

    var body: some View {
        GeometryReader { g in
            // Room outside the rim for the compass letters (12 pt out) and the rise/set labels (30 pt out, up to ~40 pt half-width).
            let r = max(40, min(g.size.width, g.size.height) / 2 - 70), c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let pt = { (p: SkyPathPoint) -> CGPoint in let o = p.chartOffset(radius: Double(r)); return CGPoint(x: c.x + o.dx, y: c.y + o.dy) }
            // A point pushed out from the centre by `by` points: rim labels go outside the circle, clear of the compass letters' band.
            let outward = { (q: CGPoint, by: CGFloat) -> CGPoint in
                let dx = q.x - c.x, dy = q.y - c.y, len = max(1, (dx * dx + dy * dy).squareRoot())
                return CGPoint(x: q.x + dx / len * by, y: q.y + dy / len * by)
            }
            ZStack {
                Circle().stroke(Color.white.opacity(0.35), lineWidth: 1).frame(width: 2 * r, height: 2 * r).position(c)
                Circle().stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: r, height: r).position(c)   // 45° up
                ForEach(Array(zip(["N", "E", "S", "W"], [0.0, 90, 180, 270])), id: \.0) { label, az in
                    Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
                        .position(outward(pt(SkyPathPoint(label: label, time: .now, azimuthDeg: az, altitudeDeg: 0)), 12))
                }
                let pts = path.map(pt)
                if pts.count >= 2, let a = pts.first, let b = pts.last {
                    let far = (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) > 4
                    if far || pts.count == 3 {
                        Path { p in
                            p.move(to: a)
                            if pts.count == 3 {
                                // A quadratic curve through the highest point: its control point sits beyond it.
                                let m = pts[1]
                                p.addQuadCurve(to: b, control: CGPoint(x: 2 * m.x - (a.x + b.x) / 2, y: 2 * m.y - (a.y + b.y) / 2))
                            } else { p.addLine(to: b) }
                        }
                        .stroke(Theme.accent, lineWidth: 2.5)
                    }
                    ForEach(Array(zip(path.indices, pts)), id: \.0) { i, q in
                        let last = i == pts.count - 1, mid = pts.count == 3 && i == 1
                        Circle().fill(last ? Theme.accent : Theme.text).frame(width: 7, height: 7).position(q)
                        Text("\(path[i].label) \(Copy.hhmm(path[i].time, site: site))").font(.system(size: 10)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 4).background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                            .fixedSize()
                            .position(mid ? CGPoint(x: q.x, y: q.y - 13) : outward(q, 30))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(path.map { "\($0.label) \(Copy.hhmm($0.time, site: site)), \(Geo.compass($0.azimuthDeg)), \(Int($0.altitudeDeg.rounded())) degrees up" }
                                .joined(separator: "; "))
    }
}

/// An event's chips, shared by its card (stacked) and its page (in a row): At peak, Fits frame or Too wide, Clear or Cloudy.
struct EventChips: View {
    let event: SkyEvent
    var onPage = false
    var body: some View {
        let chips = Group {
            if event.atPeak { Chip(text: "At peak", icon: "sparkle") }
            if let f = event.fits { Chip(text: f ? "Fits frame" : "Too wide", icon: "viewfinder") }
            if let c = event.clear { Chip(text: onPage ? (c ? "Clear then" : "Cloudy then") : (c ? "Clear" : "Cloudy"), icon: c ? "checkmark" : "cloud.fill", warning: !c) }
            if event.behindHorizon {
                Chip(text: event.kind == .meteorShower ? "Radiant behind your horizon" : "Behind your horizon", icon: "eye.slash", warning: true)
            }
        }
        if onPage { HStack(spacing: 6) { chips } } else { VStack(alignment: .trailing, spacing: 4) { chips } }
    }
}

/// "How to shoot this" (v0.6.7, owner-approved mockup), shared by a target's page and an event's page.
struct ShootingTipCard: View {
    let tip: ShootingTip
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Label(tip.title, systemImage: tip.symbol).font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)   // wraps rather than cutting a long telescope name short
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let line = tip.copyLine { CopyButton(text: line, label: "Copy settings", done: "Settings copied") }   // #61
            }
            ForEach(tip.rows, id: \.label) { r in
                HStack(alignment: .top, spacing: 8) {
                    Text(r.label).font(.system(size: 11)).foregroundStyle(Theme.dim).frame(width: 64, alignment: .leading)
                    Text(r.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let src = tip.source { Text(src).font(.system(size: 10)).foregroundStyle(Theme.dim) }
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .captionBacking(cornerRadius: 10)
    }
}

/// The system's copy icon (#61, owner-approved mock-up): copies `text`, then shows a tick for two seconds so the copy is
/// seen without a tooltip, and tells VoiceOver. Keyboard-reachable. The one pattern for anything worth copying.
struct CopyButton: View {
    let text: String
    let label: String
    let done: String
    @State private var copied = false
    @State private var copies = 0   // each click's own two seconds: an earlier click never cuts a later tick short

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            copies += 1
            let this = copies
            AccessibilityNotification.Announcement(done).post()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if copies == this { copied = false } }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: copied ? .bold : .regular))
                .foregroundStyle(copied ? Tokens.accentClear : Theme.text)
                .frame(width: 28, height: 28)
                .background(copied ? Tokens.accentClear.opacity(0.25) : Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)   // constant: the announcement says it was copied, once
    }
}

/// The "How to shoot this" toggle on a page's caption, shared by targets and events.
struct HowToShootButton: View {
    @Binding var shown: Bool
    var body: some View {
        Button { shown.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "camera.aperture").accessibilityHidden(true)
                Text("How to shoot this")
                Image(systemName: shown ? "chevron.down" : "chevron.up").font(.system(size: 9, weight: .semibold)).accessibilityHidden(true)
            }
        }
        .captionButton().padding(.top, 4)
    }
}

/// An occultation's page picture (#115): the Moon, and each covered star's path behind it, drawn as the sky looks
/// facing it, north up and east to the left. A dot marks where the star starts its path; its name sits beside it.
struct OccultationView: View {
    let occultation: Occultation
    let site: Site
    private static let stars = (try? BrightStars.bundled()) ?? []

    var body: some View {
        let tracks = Occultations.tracks(occultation, site: site, stars: Self.stars)
        Canvas { ctx, size in
            let r = min(size.width, size.height) * 0.3, c = CGPoint(x: size.width / 2, y: size.height / 2)
            func pt(_ p: (x: Double, y: Double)) -> CGPoint { CGPoint(x: c.x - CGFloat(p.x) * r, y: c.y - CGFloat(p.y) * r) }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.85, green: 0.83, blue: 0.78)))
            for t in tracks where t.points.count > 1 {
                var p = Path(); p.move(to: pt(t.points[0])); t.points.dropFirst().forEach { p.addLine(to: pt($0)) }
                ctx.stroke(p, with: .color(Color(red: 0.62, green: 0.82, blue: 1)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                let s = pt(t.points[0])
                ctx.fill(Path(ellipseIn: CGRect(x: s.x - 3.5, y: s.y - 3.5, width: 7, height: 7)), with: .color(.white))
                ctx.draw(Text(t.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white), at: CGPoint(x: s.x, y: s.y - 12))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The Moon and the path of \(ListFormatter.localizedString(byJoining: occultation.contacts.map(\.name))) behind it")
    }
}
