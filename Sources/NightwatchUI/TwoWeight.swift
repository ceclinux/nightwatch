import SwiftUI

/// A headline in two weights: everything heavy but the last word, which is thin ("Clear window" heavy, "tonight" thin).
public enum TwoWeight {
    public static func headline(_ text: String, size: CGFloat) -> Text {
        let words = text.split(separator: " ")
        guard words.count > 1, let last = words.last else { return Text(text).font(.system(size: size, weight: .heavy)) }
        return Text(words.dropLast().joined(separator: " ") + " ").font(.system(size: size, weight: .heavy))
            + Text(String(last)).font(.system(size: size, weight: .thin))
    }
}
