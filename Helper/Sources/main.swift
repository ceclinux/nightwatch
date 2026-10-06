import Foundation
import Darwin

// Nightwatch's one helper outside the sandbox (1.5.4). macOS goes on running the old version's widget after Nightwatch
// has been replaced by a newer one, and refuses what it draws: the widget keeps its last picture, or shows grey bars
// (owner, 6 October 2026). Ending that process is all it takes, and the app's sandbox may not do it (kill returns EPERM,
// measured the same day). So the app asks this service, once per new version, and this service does that one thing.
// It is not in the Mac App Store build, where every executable must be sandboxed.

/// Kept identical in Sources/Nightwatch/WidgetReset.swift: the two sides only share its selectors.
@objc protocol WidgetResetProtocol {
    /// Ends every running copy of Nightwatch's own widget; replies with how many it ended.
    func endWidgetProcesses(reply: @escaping (Int) -> Void)
}

final class WidgetResetService: NSObject, WidgetResetProtocol, NSXPCListenerDelegate {
    /// The only processes this will signal: this user's, running Nightwatch's widget from inside a Nightwatch.app.
    static let widgetSuffix = "/Nightwatch.app/Contents/PlugIns/NightwatchWidget.appex/Contents/MacOS/NightwatchWidget"

    func endWidgetProcesses(reply: @escaping (Int) -> Void) {
        var ended = 0
        var pids = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        for pid in pids.prefix(max(0, Int(bytes))) where pid > 0 {
            var path = [CChar](repeating: 0, count: 4096)   // PROC_PIDPATHINFO_MAXSIZE
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0, String(cString: path).hasSuffix(Self.widgetSuffix) else { continue }
            if kill(pid, SIGTERM) == 0 { ended += 1 }   // another user's copy fails here, as it should
        }
        reply(ended)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: WidgetResetProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
}

let service = WidgetResetService()
let listener = NSXPCListener.service()
listener.delegate = service
listener.resume()   // never returns for an XPC service
