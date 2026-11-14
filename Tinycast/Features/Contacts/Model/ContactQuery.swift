import Foundation

/// What the search field's text becomes before it reaches Contacts.
enum ContactQuery {
    /// Trimmed and single-spaced, so "  ada   lovelace " finds the same card as "ada lovelace".
    static func normalized(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
