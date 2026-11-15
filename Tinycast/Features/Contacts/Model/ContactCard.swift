import Foundation

/// One navigable value on a card: a number, an address, an email or the birthday.
struct ContactField: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case phone
        case email
        case address
        case birthday
    }

    let id: String
    let kind: Kind
    let label: String
    let value: String
}

/// The compact buttons above the sections; each acts on the card's first matching value.
enum ContactQuickAction: CaseIterable, Hashable, Sendable {
    case message
    case faceTime
    case email
}

/// A card's keyboard layout: the quick-action row is one stop, then one stop per field.
struct ContactCard: Equatable, Sendable {
    let contact: Contact
    let quickActions: [ContactQuickAction]
    let fields: [ContactField]

    init(_ contact: Contact, calendar: Calendar = .current, locale: Locale = .current) {
        self.contact = contact
        var actions: [ContactQuickAction] = []
        if !contact.phones.isEmpty { actions += [.message, .faceTime] }
        if !contact.emails.isEmpty { actions.append(.email) }
        quickActions = actions

        func make(_ kind: ContactField.Kind, _ entries: [Contact.Entry]) -> [ContactField] {
            entries.map { ContactField(id: $0.id, kind: kind, label: $0.label, value: $0.value) }
        }
        var all = make(.phone, contact.phones) + make(.email, contact.emails)
        all += make(.address, contact.addresses)
        if let birthday = contact.birthday,
            let text = ContactFormat.birthday(birthday, calendar: calendar, locale: locale)
        {
            all.append(
                ContactField(id: "birthday", kind: .birthday, label: "", value: text))
        }
        fields = all
    }

    var hasQuickRow: Bool { !quickActions.isEmpty }

    var stopCount: Int { (hasQuickRow ? 1 : 0) + fields.count }

    /// The field a stop stands on; nil for the quick-action row or an out-of-range stop.
    func field(atStop stop: Int) -> ContactField? {
        let index = stop - (hasQuickRow ? 1 : 0)
        return fields.indices.contains(index) ? fields[index] : nil
    }

    func stop(of field: ContactField) -> Int? {
        fields.firstIndex(of: field).map { $0 + (hasQuickRow ? 1 : 0) }
    }
}

/// Where the keyboard is: in the results list (`stop == nil`) or on one of the card's stops.
struct ContactCardFocus: Equatable, Sendable {
    private(set) var stop: Int?
    /// The highlighted quick action while the stop is the quick-action row.
    private(set) var button = 0

    var isInCard: Bool { stop != nil }

    mutating func leave() {
        stop = nil
        button = 0
    }

    /// False when the card has nothing to focus.
    @discardableResult
    mutating func enter(stops: Int) -> Bool {
        guard stops > 0 else { return false }
        stop = 0
        button = 0
        return true
    }

    mutating func focus(stop next: Int, stops: Int) {
        guard (0..<stops).contains(next) else { return }
        stop = next
        button = 0
    }

    /// ↑/↓ clamp at the ends: the way back to the list is ← or Esc, never an overshoot.
    mutating func moveVertically(_ delta: Int, stops: Int) {
        guard let stop else { return }
        advance(min(max(stop + delta, 0), max(stops - 1, 0)))
    }

    /// ⇥ walks the stops and leaves the card after the last (or before the first).
    mutating func tab(backwards: Bool, stops: Int) {
        guard let stop else { return }
        let next = stop + (backwards ? -1 : 1)
        if (0..<stops).contains(next) { advance(next) } else { leave() }
    }

    /// ←/→ inside the quick-action row move between buttons; ← at the first button, or on any
    /// field, returns to the list. → on a field does nothing.
    mutating func moveHorizontally(_ delta: Int, onQuickRow: Bool, buttons: Int) {
        guard stop != nil else { return }
        guard onQuickRow else {
            if delta < 0 { leave() }
            return
        }
        let next = button + delta
        if next < 0 { leave() } else if next < buttons { button = next }
    }

    private mutating func advance(_ next: Int) {
        if next != stop { button = 0 }
        stop = next
    }
}

/// A stable colour for a card with no photo: the same name always gets the same hue.
enum ContactMonogram {
    /// 0..<1, from FNV-1a over the name so it never changes between launches (unlike `hashValue`).
    static func hue(for name: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Double(hash % 360) / 360
    }
}
