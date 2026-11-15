import Contacts
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The only reader of Contacts: read-only, and notes are never requested.
@MainActor
@Observable
final class ContactStore {
    private(set) var access: ContactsAccess = Permissions.contactsAccess()

    @ObservationIgnored private var changeObserver: NotificationToken?

    /// A browse list stops here: a card photo each makes an unbounded list expensive to hold.
    nonisolated private static let resultLimit = 200

    /// TCC sends nothing when a grant changes in Settings, so anything acting on `access` re-reads.
    func refreshAccess() {
        access = Permissions.contactsAccess()
    }

    /// Tinycast's own consent dialog has already been accepted by the time this runs.
    func requestAccess() async -> Bool {
        let granted = await Permissions.requestContactsAccess()
        refreshAccess()
        return granted
    }

    /// Fires on any edit, from any app, so an open list never outlives the card it shows.
    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in handler() }
        }
        changeObserver = NotificationToken(token, center: center)
    }

    func stopObserving() {
        changeObserver = nil
    }

    /// Everyone for an empty query, else the cards whose name matches; sorted for display.
    @concurrent
    func contacts(matching query: String) async -> [Contact] {
        let store = CNContactStore()
        let keys = Self.listKeys()
        var found: [CNContact] = []
        if query.isEmpty {
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.unifyResults = true
            Signposts.interval("ContactsEnumerate") {
                try? store.enumerateContacts(with: request) { contact, stop in
                    found.append(contact)
                    if found.count >= Self.resultLimit || Task.isCancelled { stop.pointee = true }
                }
            }
        } else {
            let predicate = CNContact.predicateForContacts(matchingName: query)
            found = Signposts.interval("ContactsSearch") {
                (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
            }
        }
        guard !Task.isCancelled else { return [] }
        return Signposts.interval("ContactsMap") {
            Contact.sorted(found.prefix(Self.resultLimit).map(Self.contact(from:)))
        }
    }

    /// The rest of one card (addresses, birthday, thumbnail), fetched only for the card being read.
    @concurrent
    func card(for id: String) async -> Contact? {
        let found = Signposts.interval("ContactsCard") {
            try? CNContactStore().unifiedContact(withIdentifier: id, keysToFetch: Self.keys())
        }
        return found.map(Self.contact(from:))
    }

    /// A row's avatar, fetched when the row scrolls into view rather than with the list.
    @concurrent
    func thumbnail(for id: String) async -> Data? {
        let keys = [CNContactThumbnailImageDataKey] as [any CNKeyDescriptor]
        return try? CNContactStore().unifiedContact(withIdentifier: id, keysToFetch: keys)
            .thumbnailImageData
    }

    /// The full-size photo of one card, shrunk to what the detail pane can show; nil when it has none.
    @concurrent
    func photo(for id: String, maxPixel: Int) async -> Data? {
        let keys = [CNContactImageDataKey, CNContactImageDataAvailableKey] as [any CNKeyDescriptor]
        guard let card = try? CNContactStore().unifiedContact(withIdentifier: id, keysToFetch: keys),
            card.imageDataAvailable, let data = card.imageData, !Task.isCancelled
        else { return nil }
        return Self.downsampled(data, maxPixel: maxPixel) ?? data
    }

    nonisolated private static func downsampled(_ data: Data, maxPixel: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard
            let target = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            target, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(target) ? output as Data : nil
    }

    /// What a row and the search need: no photo, no postal addresses, no birthday.
    nonisolated private static func listKeys() -> [any CNKeyDescriptor] {
        [
            CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactNicknameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey
        ] as [any CNKeyDescriptor]
    }

    nonisolated private static func keys() -> [any CNKeyDescriptor] {
        [
            CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactNicknameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactPostalAddressesKey,
            CNContactBirthdayKey, CNContactThumbnailImageDataKey
        ] as [any CNKeyDescriptor]
    }

    nonisolated private static func contact(from contact: CNContact) -> Contact {
        Contact(
            id: contact.identifier, givenName: contact.givenName, familyName: contact.familyName,
            nickname: contact.nickname, organization: contact.organizationName,
            jobTitle: contact.jobTitle,
            phones: contact.phoneNumbers.map { entry($0, value: $0.value.stringValue) },
            emails: contact.emailAddresses.map { entry($0, value: $0.value as String) },
            addresses: contact.isKeyAvailable(CNContactPostalAddressesKey)
                ? contact.postalAddresses.map {
                    entry($0, value: CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress))
                } : [],
            birthday: contact.isKeyAvailable(CNContactBirthdayKey) ? contact.birthday : nil,
            thumbnail: contact.isKeyAvailable(CNContactThumbnailImageDataKey)
                ? contact.thumbnailImageData : nil)
    }

    nonisolated private static func entry<Value>(_ item: CNLabeledValue<Value>, value: String) -> Contact.Entry {
        Contact.Entry(
            id: item.identifier,
            label: item.label.map { ContactFormat.label(CNLabeledValue<Value>.localizedString(forLabel: $0)) }
                ?? "",
            value: value)
    }
}
