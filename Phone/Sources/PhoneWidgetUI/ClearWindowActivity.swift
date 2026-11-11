#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import SwiftUI

/// The clear window as a Live Activity. The facts that do not change are the attributes. The countdown is drawn by the system from the
/// two dates, so it stays right with the app closed. Nothing here needs a server, which also means nothing corrects it between runs
/// of the app: the card says which forecast it came from, and the system marks it stale when the window closes.
public struct ClearWindowAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var score: Int
        public var headline: String
        public var forecastAt: Date
        public init(score: Int, headline: String, forecastAt: Date) { self.score = score; self.headline = headline; self.forecastAt = forecastAt }
    }
    public var siteName: String
    public var windowStart: Date
    public var windowEnd: Date
    public init(siteName: String, windowStart: Date, windowEnd: Date) {
        self.siteName = siteName; self.windowStart = windowStart; self.windowEnd = windowEnd
    }
}

/// The Lock Screen and StandBy card.
public struct ClearWindowLockView: View {
    let attributes: ClearWindowAttributes
    let state: ClearWindowAttributes.ContentState
    /// True from the content's stale date, which the system applies by itself: how the card says the window is over with no app running.
    let isStale: Bool
    public init(attributes: ClearWindowAttributes, state: ClearWindowAttributes.ContentState, isStale: Bool = false) {
        self.attributes = attributes; self.state = state; self.isStale = isStale
    }
    private let lit = Color(red: 0.957, green: 0.945, blue: 0.918)
    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("\(state.score)").font(.system(size: 40, weight: .bold)).monospacedDigit().foregroundStyle(lit)
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.siteName.uppercased()).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary).lineLimit(1)
                Text(state.headline).font(.subheadline.weight(.heavy)).foregroundStyle(lit).lineLimit(1)
                if isStale {
                    Text("Clear window over").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text("clear for").font(.caption).foregroundStyle(.secondary)
                        Text(timerInterval: attributes.windowStart...attributes.windowEnd, countsDown: true)
                            .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(lit)
                        Text("· forecast").font(.caption).foregroundStyle(.secondary)
                        Text(state.forecastAt, style: .time).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
#endif
