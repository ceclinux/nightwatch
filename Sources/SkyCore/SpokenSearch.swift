import Foundation

/// Siri's words for a catalogue number, as the Targets search expects them (#72). Siri wrote "M31" as "M3 one" (owner's
/// test, 29 September 2026); it may also give "M thirty one" or "Messier 31". Only numbers straight after a catalogue
/// prefix are touched, so a name such as "Seven Sisters" is left alone.
public enum SpokenSearch {
    private static let prefixes = ["m": "M", "messier": "M", "c": "C", "caldwell": "C", "ngc": "NGC", "ic": "IC"]
    private static let small = ["zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                                "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
                                "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19]
    private static let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]

    public static func normalise(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        func bare(_ i: Int) -> String { words[i].trimmingCharacters(in: .punctuationCharacters).lowercased() }
        /// The digits the words from `i` on spell, and the index after them; nil when word `i` is not a number.
        func digits(at i: Int) -> (String, Int)? {
            guard i < words.count else { return nil }
            let w = bare(i)
            if !w.isEmpty, w.allSatisfy(\.isNumber) { return (w, i + 1) }
            if let t = tens[w] {
                if i + 1 < words.count, let u = small[bare(i + 1)], u < 10 { return (String(t + u), i + 2) }
                return (String(t), i + 1)
            }
            return small[w].map { (String($0), i + 1) }
        }
        var out: [String] = [], i = 0
        while i < words.count {
            let w = bare(i), letters = String(w.prefix { $0.isLetter }), attached = String(w.dropFirst(letters.count))
            if let prefix = prefixes[letters], attached.allSatisfy(\.isNumber) {
                var number = attached, j = i + 1
                while let (d, next) = digits(at: j) { number += d; j = next }
                if !number.isEmpty { out.append(prefix + number); i = j; continue }
            }
            out.append(words[i]); i += 1
        }
        return out.joined(separator: " ")
    }
}
