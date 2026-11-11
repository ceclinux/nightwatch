import SwiftUI
import PhotosUI
import ImageIO
import SkyCore
import PhoneCore

/// "Measure from a photo": a phone photo taken where the telescope stands gives the height of the roof or trees in the direction it faced.
/// Drag the line to the top of what is in the way; `HorizonPhoto` (SkyCore) works out its height from the photo's direction, lens and tilt.
/// The photo is read here and not kept: only the degrees go back to the horizon sheet.
struct MeasurePhotoSheet: View {
    let site: Site
    let unit: DistanceUnit
    let onUse: (_ direction: Int, _ degrees: Double) -> Void
    let onMove: (Coordinate) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.phoneTheme) private var theme
    @State private var picked: PhotosPickerItem?
    @State private var image: Image?
    @State private var photo: HorizonPhoto?
    @State private var failed = false
    @State private var skylineY: Double = 0
    @State private var pickedDirection: Int?
    @State private var moved = false

    private static let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
    private var direction: Int? { photo?.direction ?? pickedDirection }
    private var measured: Double? { photo?.altitude(atY: skylineY) }
    /// The line at the very top: what is in the way runs off the photo, so the reading is only a minimum.
    private var offTop: Bool { photo.map { skylineY <= $0.height * 0.01 } ?? false }
    private var value: Double? { measured.map(HorizonPhoto.horizonValue) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Drag the line to the top of the roof, tree or hill in the way. Nightwatch works out its height from the way the phone was facing and tilted.")
                        .font(.footnote).secondary()
                    PhotosPicker(selection: $picked, matching: .images) {
                        Label(photo == nil ? "Choose a photo" : "Choose another photo", systemImage: "photo").font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 48).cardSurface()
                    }
                    if failed { problem("Nightwatch can't open this as a photo", "Choose the original from the Photos app.") }
                    if let photo, let image { picture(image, photo); readings(photo) }
                    Text("A guide, not a survey. The photo is read and not kept; only the degrees are saved.").font(.footnote).secondary()
                }
                .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(theme.background)
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Measure from a photo").font(.headline).foregroundStyle(theme.textPrimary) }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(useTitle) { if let d = direction, let v = value { Haptic.success(); onUse(d, v); dismiss() } }.disabled(direction == nil || value == nil)
                }
            }
        }
        .onChange(of: picked) { _, item in Task { await load(item) } }
        .onChange(of: Int((measured ?? 0).rounded())) { _, _ in if photo != nil { Haptic.selection() } }   // a tick for each degree the line passes
    }

    private var useTitle: String {
        guard let d = direction, let v = value else { return "Use" }
        return offTop ? "Use at least \(Int(v))° for \(Site.horizonDirections[d])" : "Use \(Int(v))° for \(Site.horizonDirections[d])"
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let props = CGImageSourceCreateWithData(data as CFData, nil).flatMap({ CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }),
              let img = Image(platformData: data) else { failed = true; photo = nil; image = nil; return }
        failed = false; moved = false; pickedDirection = nil
        let p = HorizonPhoto(properties: props)
        photo = p; image = img
        skylineY = p.height * 0.3
    }

    private func picture(_ image: Image, _ photo: HorizonPhoto) -> some View {
        let aspect = photo.width / max(1, photo.height)
        return image.resizable().aspectRatio(aspect, contentMode: .fit).frame(maxHeight: 440).frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { g in
                    let scale = g.size.height / max(1, photo.height)
                    ZStack(alignment: .topLeading) {
                        if let ly = photo.levelY {
                            Rectangle().stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 4])).frame(width: g.size.width, height: 1).offset(y: ly * scale)
                            Text(photo.pitchDeg == nil ? "Level, assumed" : "Level, 0°").font(.caption2).foregroundStyle(.white)
                                .padding(.horizontal, 5).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4)).offset(x: 8, y: ly * scale - 18)
                        }
                        if photo.focalPx != nil {
                            Rectangle().fill(theme.accent).frame(width: g.size.width, height: 2).offset(y: skylineY * scale - 1)
                            Text(measured.map { "\(Int($0.rounded()))°" } ?? "").font(.caption.weight(.semibold)).foregroundStyle(theme.isRed ? Color.black : Color(hex: 0x0A1022))
                                .frame(width: 52, height: 28).background(theme.accent, in: Capsule()).overlay(Capsule().stroke(.white, lineWidth: 2))
                                .offset(x: g.size.width / 2 - 26, y: skylineY * scale - 14)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in skylineY = min(photo.height, max(0, v.location.y / scale)) })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Skyline")
                    .accessibilityValue(measured.map { "\(Int($0.rounded())) degrees" } ?? "")
                    .accessibilityAdjustableAction { dir in step(dir == .increment ? 1 : -1, photo) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Moves the line by about a degree, for VoiceOver.
    private func step(_ degrees: Double, _ photo: HorizonPhoto) {
        guard let f = photo.focalPx else { return }
        skylineY = min(photo.height, max(0, skylineY - f * tan(degrees * .pi / 180)))
    }

    @ViewBuilder private func readings(_ photo: HorizonPhoto) -> some View {
        if photo.focalPx == nil {
            problem("Can't tell how wide the lens sees", "This photo has no lens details (a screenshot or an edited copy, perhaps). Use the original photo from the phone.")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Top of what is in the way").font(.caption).secondary()
                Text(measured.map { "\(offTop ? "More than " : "")\(Int($0.rounded()))°" } ?? "-").font(.system(size: offTop ? 24 : 34, weight: .semibold)).monospacedDigit()
            }
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    if let b = photo.bearingDeg, let d = photo.direction { fact("Facing", "\(Int(b.rounded()))°, \(Self.names[d])") }
                    fact("Tilted", photo.pitchDeg.map { p in abs(p) < 0.5 ? "Level" : "\(Int(abs(p).rounded()))° \(p > 0 ? "up" : "down"), allowed for" } ?? "Not known")
                    if let f = photo.focalPx { fact("Lens", "\(Int((2 * atan(photo.height / 2 / f) * 180 / .pi).rounded()))° top to bottom") }
                    if let place = photo.place(relativeTo: site) { takenAt(place) }
                }
            }
            if case .near = photo.place(relativeTo: site), let t = photo.taken, !moved {
                Text("If this is where the telescope stands, \(site.name) can move here. Forecasts and darkness hardly change over this distance; dark sites are measured from the new spot.")
                    .font(.footnote).secondary()
                SecondaryButton(title: "Move \(site.name) here", systemImage: "location") { Haptic.success(); onMove(t); moved = true }
            }
            if case .far = photo.place(relativeTo: site) {
                Text("A horizon belongs to where it was measured. Use a photo taken where the telescope stands at \(site.name), or add the place it was taken as a site of its own.")
                    .font(.footnote).secondary()
            }
            if photo.direction == nil {
                problem("No compass direction in this photo", "It was taken with location off, or on another camera. Which way were you facing?")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        Button { Haptic.selection(); pickedDirection = i } label: {
                            Text(Site.horizonDirections[i]).font(.callout.weight(pickedDirection == i ? .semibold : .regular)).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(pickedDirection == i ? (theme.isRed ? Color.black : Color(hex: 0x0A1022)) : theme.textPrimary)
                                .background(pickedDirection == i ? theme.accent : theme.track, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(PressStyle())
                    }
                }
            }
            if photo.pitchDeg == nil {
                problem("No tilt reading: assuming the phone was level", "Only iPhone photos say how the phone was tilted. For the best guess from another camera, hold it upright and level.")
            }
            if offTop {
                problem("It goes off the top of the photo", "So it is higher than this. Take another with the phone tilted up, or use this as the least it can be.")
            }
            if let d = direction, let v = value {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set \(Site.horizonDirections[d]) to \(offTop ? "at least " : "")\(Int(v))°").font(.callout.weight(.semibold))
                        Text("Rounded up to the next 5°, so a target counts as up only once it is clear of it.").font(.footnote).secondary()
                    }
                }
            }
        }
    }

    @ViewBuilder private func takenAt(_ place: HorizonPhoto.Place) -> some View {
        switch place {
        case .asSet: fact("Taken at", "\(site.name), as set")
        case .near(let km): fact("Taken at", moved ? "\(site.name) moved to where this photo was taken." : "\(HorizonPhoto.distanceText(km: km, unit: unit)) from where \(site.name) is set")
        case .far(let km): fact("Taken at", "! \(HorizonPhoto.distanceText(km: km, unit: unit)) from \(site.name): is it the right photo?")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(label).font(.caption).secondary().frame(width: 72, alignment: .leading); Text(value).font(.footnote) }
    }

    private func problem(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold))
            Text(text).font(.footnote).secondary().fixedSize(horizontal: false, vertical: true)
        }
    }
}
