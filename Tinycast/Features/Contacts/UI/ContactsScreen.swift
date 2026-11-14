import SwiftUI

/// Search the address book and act on a card: copy, email, message, FaceTime or open it.
struct ContactsScreen: PaletteScreen {
    let session: ContactsSession
    let coordinator: ContactsCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [Contact] { session.contacts }

    var primaryActionTitle: String { String(localized: "Open in Contacts") }

    private func contact(at selection: Int) -> Contact? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func hasPrimaryAction(at selection: Int) -> Bool { contact(at: selection) != nil }

    func activate(at selection: Int) {
        guard let contact = contact(at: selection) else { return }
        coordinator.openInContacts(contact)
    }

    /// ⌘↵ — the name, for pasting into a message or a document.
    func secondary(at selection: Int) -> Bool {
        guard let contact = contact(at: selection) else { return false }
        coordinator.copy(contact.displayName, message: String(localized: "Copied name"))
        return true
    }

    // MARK: - Actions

    /// A card with several numbers gets a row per number, each stating its label and value.
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let contact = contact(at: selection) else { return nil }
        var items = [
            PopoverMenuItem(
                title: String(localized: "Open in Contacts"), systemImage: "person.crop.circle",
                shortcut: "↵"
            ) { coordinator.openInContacts(contact) },
            PopoverMenuItem(
                title: String(localized: "Copy Name"), systemImage: "doc.on.doc", shortcut: "⌘↵"
            ) { coordinator.copy(contact.displayName, message: String(localized: "Copied name")) }
        ]
        for phone in contact.phones {
            items.append(
                row(
                    String(localized: "Message"), "message", phone, first: phone == contact.phones.first
                ) { coordinator.open(ContactFormat.messageURL(phone.value)) })
            items.append(
                row(String(localized: "FaceTime"), "video", phone) {
                    coordinator.open(ContactFormat.faceTimeURL(phone.value))
                })
            items.append(
                row(String(localized: "Copy Phone Number"), "phone", phone) {
                    coordinator.copy(phone.value)
                })
        }
        for email in contact.emails {
            items.append(
                row(
                    String(localized: "Send Email"), "envelope", email,
                    first: email == contact.emails.first
                ) { coordinator.open(ContactFormat.mailURL(email.value)) })
            items.append(
                row(String(localized: "Copy Email"), "at", email) { coordinator.copy(email.value) })
        }
        for address in contact.addresses {
            items.append(
                row(
                    String(localized: "Copy Address"), "mappin.and.ellipse", address,
                    first: address == contact.addresses.first
                ) { coordinator.copy(address.value) })
        }
        return PopoverMenuContent(header: contact.displayName, items: items)
    }

    private func row(
        _ title: String, _ symbol: String, _ entry: Contact.Entry, first: Bool = false,
        action: @escaping () -> Void
    ) -> PopoverMenuItem {
        let detail = [entry.label, ContactFormat.oneLine(entry.value)].filter { !$0.isEmpty }
            .joined(separator: "  ")
        return PopoverMenuItem(
            title: title, icon: .symbol(symbol), startsSection: first, detail: detail, action: action)
    }

    // MARK: - Body

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            ContactsView(
                session: session, rows: rows, selection: selection, scroll: scroll,
                onSelect: { vm.selection = $0 },
                onActivate: { activate(at: vm.selection) },
                onActions: { index in
                    vm.selection = index
                    openActions()
                }
            )
            .onAppear { session.start(query: vm.query) }
            .onDisappear { session.end() }
            .onChange(of: vm.query) { _, query in session.setQuery(query) })
    }
}
