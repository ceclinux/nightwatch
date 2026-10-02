// Says where Nightwatch stands with App Review, from the App Store Connect API, and whether it is waiting on us.
//
// Usage: swift scripts/review-status.swift
//
// Written on 2 October 2026 after 1.0.0 sat "Rejected" for a day: the reply to App Review had been sent, but nothing puts
// a rejected version back in the queue except Save and Resubmit, and App Store Connect sends no reminder. This prints
// each version's state in plain words, and exits 1 when something needs doing. The version state is enough: Rejected,
// and Ready for Review (saved but not resubmitted), are the two states that went unnoticed. The review-submission list
// would need a Developer key (a Sales and Reports key gets 403, checked 2 October 2026), so it is left out.
//
// The key: a Team API key with the Sales and Reports role (read-only for apps), made in App Store Connect › Users and Access ›
// Integrations. Its parts live in the login keychain (docs/app-store.md, "Checking the review status"):
//   nightwatch-asc-key-id, nightwatch-asc-issuer-id, nightwatch-asc-key (the .p8 file, base64)
// ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (a .p8 file) override them, for testing with another key.
import CryptoKit
import Foundation
import Security

let appID = "6816390602"   // Nightwatch: Clear Sky Alerts
let api = "https://api.appstoreconnect.apple.com/v1"

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(("review-status: " + message + "\n").data(using: .utf8)!)
    exit(code)
}

func keychain(_ service: String) -> String? {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

let env = ProcessInfo.processInfo.environment
let howTo = "see docs/app-store.md, \"Checking the review status\""
guard let keyID = env["ASC_KEY_ID"] ?? keychain("nightwatch-asc-key-id") else { fail("no key ID in the keychain: \(howTo)") }
guard let issuer = env["ASC_ISSUER_ID"] ?? keychain("nightwatch-asc-issuer-id") else { fail("no issuer ID in the keychain: \(howTo)") }
let pem: String
if let path = env["ASC_KEY_PATH"] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
    pem = text
} else {
    guard let b64 = keychain("nightwatch-asc-key"), let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
          let text = String(data: data, encoding: .utf8) else { fail("no private key in the keychain: \(howTo)") }
    pem = text
}
guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else { fail("the private key is not a valid .p8 file") }

// A JSON Web Token signed with the key (ES256), valid for 10 minutes; Apple allows up to 20.
func base64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
func json(_ o: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) }
let now = Int(Date().timeIntervalSince1970)
let unsigned = base64url(json(["alg": "ES256", "kid": keyID, "typ": "JWT"])) + "."
    + base64url(json(["iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"]))
guard let signature = try? key.signature(for: Data(unsigned.utf8)) else { fail("could not sign the token") }
let token = unsigned + "." + base64url(signature.rawRepresentation)

func get(_ path: String) -> [[String: Any]] {
    var request = URLRequest(url: URL(string: api + path)!)
    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    var result: (Data?, URLResponse?, Error?)
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { result = ($0, $1, $2); done.signal() }.resume()
    done.wait()
    if let error = result.2 { fail("App Store Connect did not answer: \(error.localizedDescription)") }
    let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
    let body = result.0.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    guard status == 200, let rows = body?["data"] as? [[String: Any]] else {
        let detail = ((body?["errors"] as? [[String: Any]])?.first?["detail"] as? String) ?? "no detail"
        switch status {
        case 401: fail("App Store Connect refused the key (401): check the key ID, issuer ID and .p8 file. \(detail)")
        case 403: fail("the key's role cannot read this (403). \(detail)")
        default: fail("App Store Connect answered \(status): \(detail)")
        }
    }
    return rows
}

// What each state means for us. True: it is waiting on us, not on Apple.
let versionStates: [String: (String, Bool)] = [
    "PREPARE_FOR_SUBMISSION": ("being prepared, not submitted", false),
    "READY_FOR_REVIEW": ("saved but NOT submitted: press Resubmit to App Review", true),
    "WAITING_FOR_REVIEW": ("in Apple's queue", false),
    "IN_REVIEW": ("being reviewed now", false),
    "REJECTED": ("rejected: reply, update the Notes, Save, then Resubmit (docs/app-store.md)", true),
    "METADATA_REJECTED": ("metadata rejected: fix the listing, then Resubmit", true),
    "INVALID_BINARY": ("the build was refused: upload a new one", true),
    "DEVELOPER_REJECTED": ("withdrawn by us", true),
    "WAITING_FOR_EXPORT_COMPLIANCE": ("waiting for our export compliance answer", true),
    "PENDING_DEVELOPER_RELEASE": ("APPROVED: waiting for us to release it", true),
    "PENDING_APPLE_RELEASE": ("approved, releasing on schedule", false),
    "PROCESSING_FOR_DISTRIBUTION": ("approved, being processed for the store", false),
    "ACCEPTED": ("accepted", false),
    "READY_FOR_DISTRIBUTION": ("on the App Store", false),
    "REPLACED_WITH_NEW_VERSION": ("replaced by a newer version", false),
]
var needsUs = false
func line(_ label: String, _ state: String, _ table: [String: (String, Bool)]) {
    let (words, ours) = table[state] ?? ("unknown state", true)   // an unknown state is worth a look
    if ours { needsUs = true }
    print("\(ours ? "!" : " ") \(label): \(state), \(words)")
}

print("Nightwatch: Clear Sky Alerts (\(appID)), \(ISO8601DateFormatter().string(from: Date()))")
print("Versions:")
for v in get("/apps/\(appID)/appStoreVersions?fields[appStoreVersions]=versionString,platform,appVersionState,createdDate&limit=5") {
    let a = v["attributes"] as? [String: Any] ?? [:]
    line("\(a["platform"] as? String ?? "?") \(a["versionString"] as? String ?? "?")", a["appVersionState"] as? String ?? "?", versionStates)
}
print(needsUs ? "\nSomething is waiting on us (marked !)." : "\nNothing is waiting on us.")
exit(needsUs ? 1 : 0)
