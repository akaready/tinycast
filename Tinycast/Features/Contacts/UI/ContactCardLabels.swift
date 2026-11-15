import Foundation

extension ContactQuickAction {
    var title: String {
        switch self {
        case .message: String(localized: "Message")
        case .faceTime: String(localized: "FaceTime")
        case .email: String(localized: "Send Email")
        }
    }

    var symbol: String {
        switch self {
        case .message: "message"
        case .faceTime: "video"
        case .email: "envelope"
        }
    }
}

extension ContactField {
    /// What ↵ does on the field, which is also the footer pill's label.
    var primaryTitle: String {
        switch kind {
        case .phone: String(localized: "Message")
        case .email: String(localized: "Send Email")
        case .address: String(localized: "Open in Maps")
        case .birthday: String(localized: "Copy Birthday")
        }
    }

    var primarySymbol: String {
        switch kind {
        case .phone: "message"
        case .email: "envelope"
        case .address: "map"
        case .birthday: "doc.on.doc"
        }
    }

    var copyTitle: String {
        switch kind {
        case .phone: String(localized: "Copy Phone Number")
        case .email: String(localized: "Copy Email")
        case .address: String(localized: "Copy Address")
        case .birthday: String(localized: "Copy Birthday")
        }
    }
}

extension ContactsCoordinator {
    /// ↵ on a field: write, compose or look up; a birthday has nothing to open, so it is copied.
    func performPrimary(_ field: ContactField) {
        switch field.kind {
        case .phone: open(ContactFormat.messageURL(field.value))
        case .email: open(ContactFormat.mailURL(field.value))
        case .address: open(ContactFormat.mapsURL(field.value))
        case .birthday: copyInCard(field.value, id: field.id)
        }
    }

    func perform(_ action: ContactQuickAction, on contact: Contact) {
        switch action {
        case .message: open(contact.phones.first.flatMap { ContactFormat.messageURL($0.value) })
        case .faceTime: open(contact.phones.first.flatMap { ContactFormat.faceTimeURL($0.value) })
        case .email: open(contact.emails.first.flatMap { ContactFormat.mailURL($0.value) })
        }
    }
}
