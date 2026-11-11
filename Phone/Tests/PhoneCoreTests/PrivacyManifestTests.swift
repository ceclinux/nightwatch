import Testing
import Foundation

/// The phone app's privacy manifest says what the App privacy answers say (docs/app-store.md in the Mac section, Phone/docs/app-store.md here):
/// precise location, for app functionality, not linked, not used for tracking, and nothing else. iOS also asks for a reason for each system API of
/// certain kinds; this keeps those matching what the code calls, so a newly used one fails here until the manifests are brought into line.
private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func manifest(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appendingPathComponent(path))
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

private func reasons(_ m: [String: Any]) throws -> [String: [String]] {
    Dictionary(uniqueKeysWithValues: try #require(m["NSPrivacyAccessedAPITypes"] as? [[String: Any]]).map {
        ($0["NSPrivacyAccessedAPIType"] as? String ?? "", $0["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
    })
}

private func code(_ dirs: [String]) throws -> String {
    let base = root.deletingLastPathComponent()   // the repository root, for SkyCore
    return try dirs.flatMap { dir in
        FileManager.default.enumerator(at: base.appendingPathComponent(dir), includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
}

@Test func theAppManifestMatchesThePrivacyAnswersAndTheCode() throws {
    let m = try manifest("App/PrivacyInfo.xcprivacy")
    #expect(m["NSPrivacyTracking"] as? Bool == false)
    #expect((m["NSPrivacyTrackingDomains"] as? [String]) == [])
    let collected = try #require(m["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
    #expect(collected.count == 1)
    #expect(collected[0]["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypePreciseLocation")
    #expect(collected[0]["NSPrivacyCollectedDataTypeLinked"] as? Bool == false && collected[0]["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
    #expect(collected[0]["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])

    let src = try code(["Phone/Sources", "Phone/App", "Phone/Widget", "Sources/SkyCore"])
    func uses(_ pattern: String) -> Bool { src.range(of: pattern, options: .regularExpression) != nil }
    let declared = try reasons(m)
    // CA92.1: the app's own defaults. 1C8F.1: the App Group's. C617.1: timestamps of files in the app's container or its group's.
    #expect(declared["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1", "1C8F.1"])
    #expect(uses(#"UserDefaults\.standard|@AppStorage"#) && uses(#"UserDefaults\(suiteName"#))
    #expect(declared["NSPrivacyAccessedAPICategoryFileTimestamp"] == ["C617.1"])
    #expect(uses(#"modificationDate|creationDate|contentModificationDateKey"#))
    #expect(!uses(#"systemUptime|mach_absolute_time|volumeAvailableCapacity|systemFreeSize|systemSize|activeInputModes"#))   // boot time, disk space, keyboards: none used
    #expect(declared.count == 2)
}

@Test func theWidgetManifestCollectsNothingAndDeclaresWhatItLinks() throws {
    let m = try manifest("Widget/PrivacyInfo.xcprivacy")
    #expect(m["NSPrivacyTracking"] as? Bool == false)
    #expect((m["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    let declared = try reasons(m)
    #expect(declared["NSPrivacyAccessedAPICategoryUserDefaults"] == ["1C8F.1"])   // the widget reads the App Group's defaults only
    #expect(declared["NSPrivacyAccessedAPICategoryFileTimestamp"] == ["C617.1"])
    #expect(declared.count == 2)
}
