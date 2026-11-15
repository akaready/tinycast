import Foundation

extension ContactQuickAction {
    var title: String { action.title(for: nil) }
    var symbol: String { action.symbol }

    var action: ContactAction {
        switch self {
        case .message: .message
        case .faceTime: .faceTime
        case .email: .compose
        }
    }
}

extension ContactAction {
    func title(for kind: ContactField.Kind?) -> String {
        switch self {
        case .message: String(localized: "Message")
        case .faceTime: String(localized: "FaceTime")
        case .call: String(localized: "Call")
        case .compose: String(localized: "Send Email")
        case .openInMaps: String(localized: "Open in Maps")
        case .openInContacts: String(localized: "Open in Contacts")
        case .copyName: String(localized: "Copy Name")
        case .copy:
            switch kind {
            case .phone: String(localized: "Copy Phone Number")
            case .email: String(localized: "Copy Email")
            case .address: String(localized: "Copy Address")
            case .birthday: String(localized: "Copy Birthday")
            case nil: String(localized: "Copy")
            }
        }
    }

    /// The short word beside a key cap.
    var hint: String {
        switch self {
        case .copy: String(localized: "Copy")
        default: title(for: nil)
        }
    }

    var symbol: String {
        switch self {
        case .message: "message"
        case .faceTime: "video"
        case .call: "phone"
        case .compose: "envelope"
        case .openInMaps: "map"
        case .openInContacts: "person.crop.circle"
        case .copy, .copyName: "doc.on.doc"
        }
    }
}

extension ContactsCoordinator {
    /// What a key press resolves to for a target, from the Settings choices.
    func action(for target: ContactTarget, command: Bool) -> ContactAction {
        settings.contactActions.action(for: target, command: command)
    }

    /// Runs one action on a field's value, or on the contact itself when there is no field.
    func run(_ action: ContactAction, field: ContactField?, contact: Contact) {
        let value = field?.value ?? ""
        switch action {
        case .message: open(ContactFormat.messageURL(value), via: .messages)
        case .faceTime: open(ContactFormat.faceTimeURL(value))
        case .call: open(ContactFormat.callURL(value))
        case .compose: open(ContactFormat.mailURL(value), via: .mail)
        case .openInMaps: open(ContactFormat.mapsURL(value), via: .maps)
        case .openInContacts: openInContacts(contact)
        case .copy:
            if let field { copyInCard(field.value, id: field.id) }
        case .copyName: copy(contact.displayName, message: String(localized: "Copied name"))
        }
    }

    /// A quick-action button acts on the card's first matching value.
    func perform(_ action: ContactQuickAction, on contact: Contact) {
        let field: ContactField?
        switch action {
        case .message, .faceTime:
            field = ContactCard(contact).fields.first { $0.kind == .phone }
        case .email:
            field = ContactCard(contact).fields.first { $0.kind == .email }
        }
        run(action.action, field: field, contact: contact)
    }
}
