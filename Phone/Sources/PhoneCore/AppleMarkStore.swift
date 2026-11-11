import Foundation

/// Apple Weather's mark, kept on disk the first time Apple Weather supplies a forecast, so the footer draws it at once, and
/// without a connection, and a failed download never leaves the words "Apple Weather" where the mark belongs. The mark is
/// kept exactly as Apple supplies it, never recoloured. Kept for the address it came from: a mark for another address is
/// never drawn.
public struct AppleMarkStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private var file: URL { directory.appendingPathComponent("apple-weather-mark.png") }
    private var stamp: URL { directory.appendingPathComponent("apple-weather-mark.url") }

    /// The kept mark's image data, only when it is the file for `address`.
    public func data(for address: String) -> Data? {
        guard (try? String(contentsOf: stamp, encoding: .utf8)) == address else { return nil }
        return try? Data(contentsOf: file)
    }

    public func save(_ data: Data, for address: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        try address.write(to: stamp, atomically: true, encoding: .utf8)
    }
}
