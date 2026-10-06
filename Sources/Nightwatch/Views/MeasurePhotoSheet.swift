import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import NightwatchUI
import SkyCore

/// A photo chosen for "Measure from a photo…", identified so a second choice replaces the first sheet.
struct PhotoChoice: Identifiable {
    let id = UUID()
    let url: URL

    /// An Open panel for one image; nil when cancelled.
    @MainActor static func pick() -> PhotoChoice? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo taken where the telescope stands, facing one way"
        panel.prompt = "Measure"
        return panel.runModal() == .OK ? panel.url.map { PhotoChoice(url: $0) } : nil
    }
}

/// "Measure from a photo" (owner-approved mock-up, 1 October 2026): drag the line to the top of what is in the way and
/// Nightwatch works out its height from the photo's direction, lens and tilt (`HorizonPhoto`). The photo is read here
/// and not kept: only the degrees go back to the horizon sheet.
struct MeasurePhotoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var choice: PhotoChoice
    /// The site being measured, to say where the photo was taken against it; nil skips that.
    var site: Site?
    var unit: DistanceUnit = .km
    let onUse: (_ direction: Int, _ degrees: Double) -> Void
    /// Moves the site to where the photo was taken.
    var onMove: ((Coordinate) -> Void)?
    @State private var moved = false
    @State private var image: NSImage?
    @State private var photo: HorizonPhoto?
    @State private var skylineY: Double = 0
    @State private var pickedDirection: Int?

    private static let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]

    private var direction: Int? { photo?.direction ?? pickedDirection }
    private var measured: Double? { photo?.altitude(atY: skylineY) }
    /// The line at the very top: what is in the way runs off the photo, so the reading is only a minimum.
    private var offTop: Bool { photo.map { skylineY <= $0.height * 0.01 } ?? false }
    private var value: Double? { measured.map(HorizonPhoto.horizonValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Measure from a photo").font(Font.scaled(.title3).weight(.semibold))
            Text("Drag the line to the top of the roof, tree or hill in the way. Nightwatch works out its height from the way the phone was facing and tilted.")
                .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 22) {
                picture.frame(width: 420, height: 560)
                VStack(alignment: .leading, spacing: 12) { readings }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Choose another photo…") { if let c = PhotoChoice.pick() { load(c) } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(useTitle) {
                    if let d = direction, let v = value { onUse(d, v); dismiss() }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(direction == nil || value == nil)
            }
        }
        .padding(24)
        .frame(width: 760)
        .onAppear { load(choice) }
    }

    private var useTitle: String {
        guard let d = direction, let v = value else { return "Use" }
        return offTop ? "Use at least \(Int(v))° for \(Site.horizonDirections[d])" : "Use \(Int(v))° for \(Site.horizonDirections[d])"
    }

    private func load(_ c: PhotoChoice) {
        choice = c
        image = NSImage(contentsOf: c.url)
        let props = CGImageSourceCreateWithURL(c.url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        photo = props.map(HorizonPhoto.init(properties:))
        pickedDirection = nil
        moved = false
        skylineY = (photo?.height ?? 0) * 0.3
    }

    // MARK: the photo

    @ViewBuilder private var picture: some View {
        if let image, let photo, photo.height > 0 {
            GeometryReader { g in
                let scale = min(g.size.width / photo.width, g.size.height / photo.height)
                let w = photo.width * scale, h = photo.height * scale
                let ox = (g.size.width - w) / 2, oy = (g.size.height - h) / 2
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image).resizable().frame(width: w, height: h).offset(x: ox, y: oy)
                    if let ly = photo.levelY {
                        Rectangle().stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 4])).frame(width: w, height: 1)
                            .offset(x: ox, y: oy + ly * scale)
                        Text(photo.pitchDeg == nil ? "Level, assumed" : "Level, 0°").font(.system(size: TextScale.pt(10))).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                            .offset(x: ox + 8, y: oy + ly * scale - 18)
                    }
                    if photo.focalPx != nil {
                        Rectangle().fill(Theme.accent).frame(width: w, height: 2).offset(x: ox, y: oy + skylineY * scale - 1)
                        Text(measured.map { "\(Int($0.rounded()))°" } ?? "")
                            .font(.system(size: TextScale.pt(11), weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 48, height: 24).background(Theme.accent, in: Capsule()).overlay(Capsule().stroke(.white, lineWidth: 2))
                            .offset(x: ox + w / 2 - 24, y: oy + skylineY * scale - 12)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    skylineY = min(photo.height, max(0, (v.location.y - oy) / scale))
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Skyline")
                .accessibilityValue(measured.map { "\(Int($0.rounded())) degrees" } ?? "")
                .accessibilityAdjustableAction { dir in step(dir == .increment ? 1 : -1) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06))
                .overlay(Text("Nightwatch can't open this file as a photo.").font(Font.scaled(.caption)).foregroundStyle(Theme.dim))
        }
    }

    /// Moves the line by about a degree, for the keyboard and VoiceOver.
    private func step(_ degrees: Double) {
        guard let photo, let f = photo.focalPx else { return }
        skylineY = min(photo.height, max(0, skylineY - f * tan(degrees * .pi / 180)))
    }

    // MARK: the readings

    @ViewBuilder private var readings: some View {
        if let photo {
            if photo.focalPx == nil {
                problem("Can't tell how wide the lens sees",
                        "This photo has no lens details (a screenshot or an edited copy, perhaps). Use the original photo from the phone.")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top of what is in the way").font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
                    Text(measured.map { "\(offTop ? "More than " : "")\(Int($0.rounded()))°" } ?? "–")
                        .font(.system(size: TextScale.pt(offTop ? 24 : 34), weight: .semibold)).monospacedDigit()
                }
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    if let b = photo.bearingDeg, let d = photo.direction { fact("Facing", "\(Int(b.rounded()))°, \(Self.names[d])") }
                    fact("Tilted", photo.pitchDeg.map { p in abs(p) < 0.5 ? "Level" : "\(Int(abs(p).rounded()))° \(p > 0 ? "up" : "down"), allowed for" } ?? "Not known")
                    if let f = photo.focalPx { fact("Lens", "\(Int((2 * atan(photo.height / 2 / f) * 180 / .pi).rounded()))° top to bottom") }
                    if let c = photo.covers { fact("Covers", "\(Int(c.from.rounded()))°–\(Int(c.to.rounded()))°: \(coveredDirections(c))") }
                    if let site, let place = photo.place(relativeTo: site) { takenAt(place, site: site) }
                }
                .font(Font.scaled(.caption))
                if let site, case .near = photo.place(relativeTo: site), let t = photo.taken, !moved {
                    Text("If this is where the telescope stands, \(site.name) can move here. Forecasts and darkness hardly change over this distance; dark sites are measured from the new spot.")
                        .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    Button("Move \(site.name) here") { onMove?(t); moved = true }
                }
                if let site, case .far = photo.place(relativeTo: site) {
                    Text("A horizon belongs to where it was measured. Use a photo taken where the telescope stands at \(site.name), or add the place it was taken as a site of its own.")
                        .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                if photo.direction == nil {
                    problem("No compass direction in this photo", "It was taken with location off, or on another camera. Which way were you facing?")
                    Picker("Facing", selection: $pickedDirection) {
                        ForEach(0..<8, id: \.self) { Text(Site.horizonDirections[$0]).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                if photo.pitchDeg == nil {
                    problem("No tilt reading: assuming the phone was level",
                            "Only iPhone photos say how the phone was tilted. For the best guess from another camera, hold it upright and level.")
                }
                if offTop {
                    problem("It goes off the top of the photo",
                            "So it is higher than this. Take another with the phone tilted up, or use this as the least it can be.")
                }
                if let d = direction, let v = value {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set \(Site.horizonDirections[d]) to \(offTop ? "at least " : "")\(Int(v))°").font(Font.scaled(.callout).weight(.semibold))
                        Text("Rounded up to the next 5°, so a target counts as up only once it is clear of it.")
                            .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Text("A guide, not a survey: your mileage may vary. The photo is read and not kept; only the degrees are saved.")
                .font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The directions whose centre the photo spans: "S and SW".
    private func coveredDirections(_ c: (from: Double, to: Double)) -> String {
        let inside = (0..<8).filter { i in
            let a = Double(i) * 45
            return c.from <= c.to ? (a >= c.from && a <= c.to) : (a >= c.from || a <= c.to)
        }.map { Site.horizonDirections[$0] }
        return inside.isEmpty ? "between directions" : ListFormatter.localizedString(byJoining: inside)
    }

    /// "Otley, as set", "240 m from where Otley is set", or a warning that it is far away (owner-approved mock-up).
    @ViewBuilder private func takenAt(_ place: HorizonPhoto.Place, site: Site) -> some View {
        switch place {
        case .asSet: fact("Taken at", "\(site.name), as set")
        case .near(let km):
            fact("Taken at", moved ? "\(site.name) moved to where this photo was taken."
                                   : "\(HorizonPhoto.distanceText(km: km, unit: unit)) from where \(site.name) is set")
        case .far(let km):
            GridRow {
                Text("Taken at").foregroundStyle(Theme.dim)
                Text("\(HorizonPhoto.distanceText(km: km, unit: unit)) from \(site.name): is it the right photo?").foregroundStyle(Tokens.statusWarning)
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow { Text(label).foregroundStyle(Theme.dim); Text(value) }
    }

    private func problem(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Font.scaled(.callout).weight(.semibold))
            Text(text).font(Font.scaled(.caption)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
        }
    }
}
