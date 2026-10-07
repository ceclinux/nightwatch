import SwiftUI
import NightwatchUI
import SkyCore

struct AboutView: View {
    @EnvironmentObject var store: Store
    private let notice = (try? String(contentsOfFile: Bundle.main.path(forResource: "NOTICE", ofType: nil) ?? "", encoding: .utf8)) ?? ""

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72).accessibilityHidden(true)   // the app's own icon, not a star (owner, 6 October 2026)
            Text("Nightwatch").font(Font.scaled(.title2).weight(.semibold))
            Text(L10n.format("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · MIT licence")).font(Font.scaled(.caption)).foregroundStyle(Theme.dim)
            if let u = store.availableUpdate { Link(L10n.format("Nightwatch \(u.version) is available ↗"), destination: ReleaseCheck.latestPage).font(Font.scaled(.caption)) }
            // The only way the project hears from the people using it (v0.6.7).
            HStack(spacing: 14) {
                Link(L10n.text("Website ↗"), destination: URL(string: "https://delphi-dolphin.com/nightwatch")!)
                Link(L10n.text("Send feedback ↗"), destination: URL(string: "https://github.com/rsutcliffe/nightwatch/discussions")!)
                Link(L10n.text("Report a problem ↗"), destination: URL(string: "https://github.com/rsutcliffe/nightwatch/issues/new")!)
                Link(L10n.text("Privacy ↗"), destination: URL(string: "https://github.com/rsutcliffe/nightwatch/blob/main/PRIVACY.md")!)   // App Store rule 5.1.1
            }
            .font(Font.scaled(.callout))
            Text(L10n.text("Feedback goes to GitHub Discussions; problems to GitHub Issues.")).font(Font.scaled(.caption2)).foregroundStyle(Theme.dim)
            ScrollView { Text(notice.isEmpty ? L10n.text("See NOTICE in the repository for data attributions.") : notice).font(Font.scaled(.caption)).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minHeight: TextScale.pt(110))   // squeezed to an empty box before: the window opened shorter than its contents
                .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(L10n.text("Weather data by Open-Meteo.com, or Apple Weather when signed for WeatherKit. Sky images: Digitized Sky Survey – STScI/NASA, Colored & Healpixed by CDS (ODbL 1.0), via hips2fits.")).wrapped().font(Font.scaled(.caption2)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            Link(L10n.text("Aurora alert status from AuroraWatch UK, Lancaster University ↗"), destination: AuroraSource.auroraWatchUK.link).wrapped().font(Font.scaled(.caption2))
            Link(L10n.text("Aurora forecast outside the UK and Ireland from NOAA's Space Weather Prediction Center ↗"), destination: AuroraSource.noaa.link).wrapped().font(Font.scaled(.caption2))
            Text(L10n.text("Darkness bands (Very dark to Bright) are Nightwatch's own thresholds on VIIRS upward radiance, not a Bortle class.")).wrapped().font(Font.scaled(.caption2)).foregroundStyle(Theme.dim)
            TurtleGlyph().frame(width: 28, height: 18).foregroundStyle(Theme.dim.opacity(0.6))
        }
        .padding(20).frame(width: TextScale.pt(420)).background(Theme.bg).foregroundStyle(Theme.text).preferredColorScheme(.dark)
    }
}

private extension View {
    /// A credit line in full, on as many centred lines as it needs: they were cut to one line and an ellipsis.
    func wrapped() -> some View { multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
}

/// Small original turtle silhouette. Unlabelled, decorative.
struct TurtleGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var shell = Path(); shell.addEllipse(in: CGRect(x: w * 0.2, y: h * 0.1, width: w * 0.6, height: h * 0.7))
            var head = Path(); head.addEllipse(in: CGRect(x: w * 0.78, y: h * 0.35, width: w * 0.2, height: h * 0.3))
            var legs = Path()
            for x in [0.25, 0.65] { legs.addEllipse(in: CGRect(x: w * x, y: h * 0.7, width: w * 0.12, height: h * 0.28)) }
            ctx.fill(shell, with: .foreground); ctx.fill(head, with: .foreground); ctx.fill(legs, with: .foreground)
        }
    }
}
