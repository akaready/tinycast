import Foundation

/// Every contact's search keys, folded once, so a keystroke filters in memory with no framework call.
struct ContactIndex: Sendable {
    private struct Entry: Sendable {
        let contact: Contact
        /// Given, family and nickname words: the strongest matches.
        let nameWords: [String]
        /// Company and job-title words.
        let workWords: [String]
        let emails: [String]
        let phoneDigits: [String]
    }

    private let entries: [Entry]

    /// `contacts` must already be in display order (`Contact.sorted`); ties keep it.
    init(_ contacts: [Contact]) {
        entries = contacts.map { contact in
            Entry(
                contact: contact,
                nameWords: Self.words([contact.givenName, contact.familyName, contact.nickname]),
                workWords: Self.words([contact.organization, contact.jobTitle]),
                emails: contact.emails.map { Self.fold($0.value) },
                phoneDigits: contact.phones.map { $0.value.filter(\.isASCII).filter(\.isNumber) })
        }
    }

    var contacts: [Contact] { entries.map(\.contact) }

    var count: Int { entries.count }

    /// Case- and diacritic-insensitive; every word of the query must match something on the card.
    /// Name-word prefixes rank first, then company words, then other substrings, emails and numbers.
    func matching(_ query: String) -> [Contact] {
        let tokens = ContactQuery.normalized(query).split(separator: " ").map { Self.fold(String($0)) }
        guard !tokens.isEmpty else { return contacts }
        var ranked: [(score: Int, position: Int, contact: Contact)] = []
        for (position, entry) in entries.enumerated() {
            var total = 0
            for token in tokens {
                guard let score = Self.score(token, entry) else {
                    total = -1
                    break
                }
                total += score
            }
            if total >= 0 { ranked.append((total, position, entry.contact)) }
        }
        ranked.sort { $0.score == $1.score ? $0.position < $1.position : $0.score > $1.score }
        return ranked.map(\.contact)
    }

    private static func score(_ token: String, _ entry: Entry) -> Int? {
        if entry.nameWords.contains(where: { $0.hasPrefix(token) }) { return 4 }
        if entry.workWords.contains(where: { $0.hasPrefix(token) }) { return 3 }
        if entry.nameWords.contains(where: { $0.contains(token) }) { return 2 }
        if entry.emails.contains(where: { $0.contains(token) }) { return 1 }
        let digits = token.filter(\.isASCII).filter(\.isNumber)
        if !digits.isEmpty, token.allSatisfy({ $0.isNumber || "+-().".contains($0) }),
            entry.phoneDigits.contains(where: { $0.contains(digits) }) {
            return 1
        }
        if entry.workWords.contains(where: { $0.contains(token) }) { return 1 }
        return nil
    }

    private static func words(_ parts: [String]) -> [String] {
        parts.flatMap { fold($0).split(whereSeparator: { $0.isWhitespace || $0 == "-" }) }
            .map(String.init)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
