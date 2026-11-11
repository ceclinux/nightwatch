import WidgetKit
import ActivityKit
import SwiftUI
import SkyCore
import PhoneWidgetUI

// Nightwatch's home-screen widget. It never fetches: it draws the snapshot the app wrote after its last refresh, so it can never
// disagree with the app. Small and medium.

struct NightEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let red: Bool
}

struct NightProvider: TimelineProvider {
    func placeholder(in context: Context) -> NightEntry { NightEntry(date: .now, snapshot: .sample, red: false) }
    func getSnapshot(in context: Context, completion: @escaping (NightEntry) -> Void) {
        completion(NightEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetShare.load(), red: WidgetShare.red))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NightEntry>) -> Void) {
        let now = Date()
        // The app reloads the timeline whenever it has a new forecast; this is only the backstop, so a stale line appears on time.
        completion(Timeline(entries: [NightEntry(date: now, snapshot: WidgetShare.load(), red: WidgetShare.red)], policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct NightwatchWidgetEntryView: View {
    let entry: NightEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        NightwatchWidgetView(snapshot: entry.snapshot, size: family == .systemLarge ? .large : family == .systemMedium ? .medium : .small,
                             red: entry.red, now: entry.date)
            .widgetURL(family == .systemMedium ? WidgetLink.plan.url : nil)   // small opens the app on Tonight, medium on Plan; large's rows are their own links
            .containerBackground(for: .widget) { NightwatchWidgetView.background(red: entry.red) }   // a plain card: iOS shows a widget's background solid (build 5 showed no transparency at 72%)
    }
}

struct NightwatchWidget: Widget {
    var body: some WidgetConfiguration {
        // Renamed (18 Oct 2026): iOS had kept re-showing a cached drawing of the old "NightwatchWidget" on the iPad.
        StaticConfiguration(kind: "NightwatchTonight", provider: NightProvider()) { NightwatchWidgetEntryView(entry: $0) }
            .configurationDisplayName("Tonight")
            .description("Whether tonight is worth setting up for, and when the sky is clear.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])   // the iPad's extra-large stayed a grey placeholder at every layout tried, so it is not offered
    }
}

/// The clear window as a Live Activity (Lock Screen, StandBy, Dynamic Island).
struct ClearWindowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClearWindowAttributes.self) { context in
            ClearWindowLockView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(NightwatchWidgetView.background(red: false)).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            // Active: the score and when the window closes. Stale: nothing, so the pill disappears into the hardware island instead of
            // holding a bare score for hours (the app cannot end the card while it is closed). The Lock Screen card says "over".
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("\(context.state.score)").font(.title.weight(.bold)).monospacedDigit() }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.isStale ? "Clear window over" : context.state.headline).font(.subheadline.weight(.heavy)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isStale {
                        Text(timerInterval: context.attributes.windowStart...context.attributes.windowEnd, countsDown: true)
                            .font(.caption.weight(.medium)).monospacedDigit().frame(maxWidth: 80, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.isStale {
                        HStack(spacing: 4) {
                            Text("Clear until"); Text(context.attributes.windowEnd, style: .time)
                            Text("· forecast").foregroundStyle(.secondary); Text(context.state.forecastAt, style: .time).foregroundStyle(.secondary)
                        }.font(.caption).monospacedDigit()
                    }
                }
            } compactLeading: {
                if !context.isStale { Text("\(context.state.score)").monospacedDigit() }
            } compactTrailing: {
                // The closing time, not a ticking timer: a timer takes the width of its widest form (hours, minutes, seconds) and is cut off.
                if !context.isStale { Text(context.attributes.windowEnd, style: .time).monospacedDigit().frame(maxWidth: 52) }
            } minimal: {
                if !context.isStale { Text("\(context.state.score)").monospacedDigit() }
            }
        }
    }
}

@main
struct NightwatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        NightwatchWidget()
        ClearWindowLiveActivity()
    }
}
