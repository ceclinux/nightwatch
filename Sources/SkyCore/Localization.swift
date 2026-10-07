import Foundation

/// A local UI preference, deliberately separate from the observing settings synced through iCloud.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system, english = "en", simplifiedChinese = "zh-Hans"

    public static let defaultsKey = "nightwatch.interfaceLanguage"

    public var nativeName: String {
        switch self {
        case .system: return L10n.text("Follow System")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            let code = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
            // Traditional Chinese remains English until we have a proper Traditional Chinese translation.
            if code == "zh" || code.hasPrefix("zh-hans") || code == "zh-cn" || code == "zh-sg" { return .simplifiedChinese }
            if code == "en" || code.hasPrefix("en-") { return .english }
        }
        return .english
    }

    public static func saved(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .system
    }
}

/// English source text is the stable key and fallback. Interpolated messages use numbered placeholders,
/// so translators can reorder values without translating user-entered names or interpreting format strings.
public enum L10n {
    // Scoped overrides keep tests and other consumers independent of the process's saved UI preference.
    @TaskLocal public static var languageOverride: AppLanguage?
    public static var language: AppLanguage { (languageOverride ?? AppLanguage.saved()).resolved() }
    public static var locale: Locale { Locale(identifier: language == .simplifiedChinese ? "zh-Hans" : "en_GB") }

    static let chinese: [String: String] = {
        guard let url = Bundle.module.url(forResource: "zh-Hans", withExtension: "json", subdirectory: "Resources/Localization"),
              let data = try? Data(contentsOf: url),
              let strings = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return strings
    }()

    public static func text(_ key: String, language: AppLanguage? = nil) -> String {
        (language ?? self.language).resolved() == .simplifiedChinese ? chinese[key] ?? key : key
    }

    public static func format(_ message: Message, language: AppLanguage? = nil) -> String {
        let template = text(message.key, language: language)
        // One pass over the template: a user's name containing "{1}" must never be replaced a second time.
        var result = "", rest = template[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            result += rest[..<open]
            let token = rest[rest.index(after: open)..<close]
            if let index = Int(token), message.values.indices.contains(index) { result += message.values[index] }
            else { result += rest[open...close] }
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    public struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
        let key: String
        let values: [String]
        public init(stringLiteral value: String) { key = value; values = [] }
        public init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key; values = stringInterpolation.values
        }
        public struct StringInterpolation: StringInterpolationProtocol, Sendable {
            var key = ""
            var values: [String] = []
            public init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity); values.reserveCapacity(interpolationCount)
            }
            public mutating func appendLiteral(_ literal: String) { key += literal }
            public mutating func appendInterpolation<T>(_ value: T) {
                key += "{\(values.count)}"; values.append(String(describing: value))
            }
        }
    }
}
