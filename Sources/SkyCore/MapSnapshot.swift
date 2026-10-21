import Foundation

public enum MapSnapshot {
    /// Apple Maps draws a pale cream grid, with no error, when it cannot fetch its tiles (seen 18 October 2026: the cards showed the grid,
    /// and the app had kept it for 30 days). A real map snapshot is dark (the snapshots are made in the dark appearance), so a picture
    /// that is almost all bright is that placeholder. `brightness` is the picture's brightness, 0 to 1, sampled on a coarse grid.
    /// ponytail: a brightness test; a light-appearance map would pass as blank, so keep the snapshots dark.
    public static func isBlank(brightness: [Double]) -> Bool {
        guard !brightness.isEmpty else { return false }
        return Double(brightness.filter { $0 > 0.7 }.count) / Double(brightness.count) >= 0.9
    }
}
