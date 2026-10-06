import Foundation
import WidgetKit

/// Kept identical in Helper/Sources/main.swift: the two sides only share its selectors.
@objc protocol WidgetResetProtocol {
    func endWidgetProcesses(reply: @escaping (Int) -> Void)
}

/// After an update, macOS goes on running the old version's widget and refuses what it draws (owner, 6 October 2026).
/// The app may not end that process from its sandbox, so once per new version it asks the helper to
/// (Helper/Sources/main.swift), then has macOS draw the widget again from the new copy.
enum WidgetReset {
    private static let key = "widgetResetForBuild"

    static func afterAnUpdate() {
        guard Distribution.hasWidgetHelper,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              UserDefaults.standard.string(forKey: key) != build else { return }
        let connection = NSXPCConnection(serviceName: "io.github.rsutcliffe.nightwatch.widgetreset")
        connection.remoteObjectInterface = NSXPCInterface(with: WidgetResetProtocol.self)
        connection.resume()
        // No helper (a build of your own without signing): nothing is recorded, so a later copy with one still runs it.
        let helper = connection.remoteObjectProxyWithErrorHandler { _ in connection.invalidate() } as? WidgetResetProtocol
        helper?.endWidgetProcesses { _ in
            UserDefaults.standard.set(build, forKey: key)
            connection.invalidate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
}
