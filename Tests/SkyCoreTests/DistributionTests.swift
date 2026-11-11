import Testing
import Foundation

/// The download and the Mac App Store build come from one codebase. Their only difference is the update check, behind one
/// `#if APPSTORE` in Sources/Nightwatch/Distribution.swift. A second one anywhere means the builds are drifting apart:
/// decide it on purpose and update this test.
@Test func theAppStoreBuildDiffersInExactlyOnePlace() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let files = ["Sources", "Widget/Sources"].flatMap { dir in
        FileManager.default.enumerator(at: root.appendingPathComponent(dir), includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
    let hits = try files.flatMap { url in
        try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            .filter { $0.range(of: #"^\s*#(if|elseif)\b.*\bAPPSTORE\b"#, options: .regularExpression) != nil }
            .map { _ in url.path.replacingOccurrences(of: root.path + "/", with: "") }
    }
    #expect(hits == ["Sources/Nightwatch/Distribution.swift"])
}

/// The privacy manifest (PrivacyInfo.xcprivacy, added for 1.7.0) says the same as the App privacy answers given to Apple
/// (docs/app-store.md): precise location, for app functionality, not linked and not used for tracking, and nothing else.
/// Apple asks for collected data on every platform. It asks for reasons for certain system APIs on iOS and its relatives
/// only, not macOS; they are declared anyway, and this keeps them matching what the code calls. A new kind of data sent
/// off the Mac, or one of those APIs newly used, should fail here until the manifest and the answers are brought into line.
@Test func thePrivacyManifestMatchesThePrivacyAnswersAndTheCode() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Sources/Nightwatch/PrivacyInfo.xcprivacy"))
    let manifest = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(manifest["NSPrivacyTracking"] as? Bool == false)
    #expect((manifest["NSPrivacyTrackingDomains"] as? [String]) == [])
    let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
    #expect(collected.count == 1)
    #expect(collected[0]["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypePreciseLocation")
    #expect(collected[0]["NSPrivacyCollectedDataTypeLinked"] as? Bool == false && collected[0]["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
    #expect(collected[0]["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])

    let declared = Dictionary(uniqueKeysWithValues: try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]).map {
        ($0["NSPrivacyAccessedAPIType"] as? String ?? "", $0["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
    })
    let code = try ["Sources", "Widget/Sources"].flatMap { dir in
        FileManager.default.enumerator(at: root.appendingPathComponent(dir), includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    func uses(_ pattern: String) -> Bool { code.range(of: pattern, options: .regularExpression) != nil }
    // CA92.1: the app's own defaults only. C617.1: timestamps of files inside the app's container or its group's.
    #expect(declared["NSPrivacyAccessedAPICategoryUserDefaults"] == (uses(#"UserDefaults|@AppStorage"#) ? ["CA92.1"] : nil))
    #expect(declared["NSPrivacyAccessedAPICategoryFileTimestamp"] == (uses(#"modificationDate|creationDate|contentModificationDateKey"#) ? ["C617.1"] : nil))
    #expect(!uses(#"UserDefaults\(suiteName"#))   // a shared suite would need 1C8F.1 as well
    #expect(!uses(#"systemUptime|mach_absolute_time|volumeAvailableCapacity|systemFreeSize|systemSize|activeInputModes"#))   // boot time, disk space, keyboards: none used
    #expect(declared.count == 2)
}
