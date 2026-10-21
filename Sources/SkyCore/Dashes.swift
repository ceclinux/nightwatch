import Foundation

extension String {
    /// The text with every en dash and em dash turned into a plain hyphen. SkyCore's wording uses an en dash in time ranges;
    /// the redesigned screens show hyphens (owner, 18 October 2026). Apply it to wording on its way to the screen, never to
    /// anything that is parsed, compared or stored.
    public var plainDashes: String {
        replacingOccurrences(of: "\u{2014}", with: "-").replacingOccurrences(of: "\u{2013}", with: "-")
    }
}
