import SwiftUI
import SkyCore

struct AboutView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow
    private let notice = (try? String(contentsOfFile: Bundle.main.path(forResource: "NOTICE", ofType: nil) ?? "", encoding: .utf8)) ?? ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "star").font(.system(size: 36)).foregroundStyle(Theme.accent)
            Text("Nightwatch").font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · MIT licence").font(.caption).foregroundStyle(Theme.dim)
            if let u = store.availableUpdate { Link("Nightwatch \(u.version) is available ↗", destination: u.url).font(.caption) }
            // The only way the project hears from the people using it (v0.6.7).
            HStack(spacing: 14) {
                Link("Website ↗", destination: URL(string: "https://delphi-dolphin.com/nightwatch")!)
                Link("Send feedback ↗", destination: URL(string: "https://github.com/rsutcliffe/nightwatch/discussions")!)
                Link("Report a problem ↗", destination: URL(string: "https://github.com/rsutcliffe/nightwatch/issues/new")!)
                Link("Privacy ↗", destination: URL(string: "https://github.com/rsutcliffe/nightwatch/blob/main/PRIVACY.md")!)   // App Store rule 5.1.1
            }
            .font(.callout)
            Button("What the numbers mean") { openWindow(id: "numbers") }.font(.callout)   // #59
            Text("Feedback goes to GitHub Discussions; problems to GitHub Issues.").font(.caption2).foregroundStyle(Theme.dim)
            ScrollView { Text(notice.isEmpty ? "See NOTICE in the repository for data attributions." : notice).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Weather data by Open-Meteo.com, or Apple Weather when signed for WeatherKit. Sky images: Digitized Sky Survey – STScI/NASA, Colored & Healpixed by CDS (ODbL 1.0), via hips2fits.").font(.caption2).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            Link("Aurora alert status from AuroraWatch UK, Lancaster University ↗", destination: AuroraSource.auroraWatchUK.link).font(.caption2)
            Link("Aurora forecast outside the UK and Ireland from NOAA's Space Weather Prediction Center ↗", destination: AuroraSource.noaa.link).font(.caption2)
            Text("Darkness bands (Very dark to Bright) are Nightwatch's own thresholds on VIIRS upward radiance, not a Bortle class.").font(.caption2).foregroundStyle(Theme.dim)
            TurtleGlyph().frame(width: 28, height: 18).foregroundStyle(Theme.dim.opacity(0.6))
        }
        .padding(20).frame(width: 420).background(Theme.bg).foregroundStyle(Theme.text).preferredColorScheme(.dark)
    }
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
