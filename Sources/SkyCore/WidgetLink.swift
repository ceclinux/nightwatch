import Foundation

/// Where a click on the desktop widget goes (v0.6): the Targets window, or one target's detail in it.
/// `nightwatch://targets` and `nightwatch://target/<id>`, the id percent-encoded so "/" or a space in it survives.
public enum WidgetLink: Equatable, Sendable {
    case targets
    case target(String)
    /// The Targets window with its search field filled in (Siri's in-app search, #72).
    case search(String)

    public static let scheme = "nightwatch"
    /// RFC 3986's unreserved characters; everything else in an id is percent-encoded.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public var url: URL {
        switch self {
        case .targets: URL(string: "\(Self.scheme)://targets")!
        case .target(let id): URL(string: "\(Self.scheme)://target/\(id.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? id)")!
        case .search(let text): URL(string: "\(Self.scheme)://search?q=\(text.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? "")")!
        }
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch c.host {
        case "targets": self = .targets
        case "target":
            guard let id = String(c.percentEncodedPath.dropFirst()).removingPercentEncoding, !id.isEmpty else { return nil }
            self = .target(id)
        case "search":
            self = .search(c.queryItems?.first { $0.name == "q" }?.value ?? "")
        default: return nil
        }
    }
}
