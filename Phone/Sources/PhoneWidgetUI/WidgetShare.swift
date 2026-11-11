import Foundation
import SkyCore

/// How the app hands the widget what to draw: the same snapshot the Tonight page was built from, kept in the shared App Group's
/// defaults, so the widget can never disagree with the app. The widget never fetches anything.
public enum WidgetShare {
    public static let group = "group.io.github.rsutcliffe.nightwatch.phone"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    /// Apple Weather's mark as a file in the group (a widget cannot fetch it), with the address it came from beside it, as the Mac keeps it.
    private static let markName = "apple-weather-mark.png"
    private static var markDir: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }

    /// Keep the mark the app holds for `address`. Nothing is written when the file for that address is already there.
    public static func saveMark(_ data: Data, for address: String) {
        guard let dir = markDir else { return }
        let stamp = dir.appendingPathComponent(markName + ".url")
        if (try? String(contentsOf: stamp, encoding: .utf8)) == address, FileManager.default.fileExists(atPath: dir.appendingPathComponent(markName).path) { return }
        try? data.write(to: dir.appendingPathComponent(markName), options: .atomic)
        try? address.write(to: stamp, atomically: true, encoding: .utf8)
    }

    /// The kept mark's image data, nil until the app has saved one.
    public static func loadMark() -> Data? {
        markDir.flatMap { try? Data(contentsOf: $0.appendingPathComponent(markName)) }
    }

    public static func save(_ snapshot: WidgetSnapshot) {
        var s = snapshot
        if s.weatherLegalURL != nil, loadMark() != nil { s.weatherMarkFile = markName }   // only when Apple Weather supplied this forecast
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(s) { defaults?.set(data, forKey: "snapshot") }
    }

    public static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: "snapshot") else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    /// Red night mode, per device, mirrored here so the widget follows it.
    public static var red: Bool {
        get { defaults?.bool(forKey: "red") ?? false }
        set { defaults?.set(newValue, forKey: "red") }
    }
}
