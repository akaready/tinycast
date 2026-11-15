import Foundation

/// One person as the screen needs them: values already read out of Contacts, notes left behind.
struct Contact: Identifiable, Equatable, Sendable {
    /// A labelled phone number, address or email, in the order the person's card lists them.
    struct Entry: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let value: String
    }

    let id: String
    let givenName: String
    let familyName: String
    let nickname: String
    let organization: String
    let jobTitle: String
    let phones: [Entry]
    let emails: [Entry]
    let addresses: [Entry]
    let birthday: DateComponents?
    let thumbnail: Data?

    init(
        id: String, givenName: String = "", familyName: String = "", nickname: String = "",
        organization: String = "", jobTitle: String = "", phones: [Entry] = [],
        emails: [Entry] = [], addresses: [Entry] = [], birthday: DateComponents? = nil,
        thumbnail: Data? = nil
    ) {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.nickname = nickname
        self.organization = organization
        self.jobTitle = jobTitle
        self.phones = phones
        self.emails = emails
        self.addresses = addresses
        self.birthday = birthday
        self.thumbnail = thumbnail
    }

    /// A card with no name still has to be findable, so it falls back to whatever identifies it.
    var displayName: String {
        let person = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let fallbacks = [nickname, organization, emails.first?.value, phones.first?.value]
        return ([person] + fallbacks.map { $0 ?? "" }).first { !$0.isEmpty }
            ?? String(localized: "(No Name)")
    }

    /// Role and company, or whichever of the two the card has; empty for a card with neither.
    var subtitle: String {
        [jobTitle, organization].filter { !$0.isEmpty && $0 != displayName }
            .joined(separator: " · ")
    }

    /// Up to two letters for the avatar a card with no photo gets.
    var initials: String {
        let parts = [givenName, familyName].filter { !$0.isEmpty }
        let source = parts.isEmpty ? [displayName] : parts
        return source.compactMap(\.first).prefix(2).map { String($0).localizedUppercase }.joined()
    }

    var isEmpty: Bool {
        phones.isEmpty && emails.isEmpty && addresses.isEmpty && birthday == nil
    }

    static func sorted(_ contacts: [Contact]) -> [Contact] {
        contacts.sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
