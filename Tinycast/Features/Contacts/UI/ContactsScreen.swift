import SwiftUI

/// Search the address book and act on a card: copy, email, message, FaceTime or open it.
struct ContactsScreen: PaletteScreen {
    let session: ContactsSession
    let coordinator: ContactsCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [Contact] { session.contacts }

    var primaryActionTitle: String {
        switch focusTarget(at: vm.selection) {
        case .quick(let action): action.title
        case .field(let field): field.primaryTitle
        case nil: String(localized: "Open in Contacts")
        }
    }

    private func contact(at selection: Int) -> Contact? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func card(at selection: Int) -> ContactCard? {
        contact(at: selection).map { ContactCard($0) }
    }

    /// What the card's keyboard focus stands on, or nil while the list owns the keys.
    private enum FocusTarget {
        case quick(ContactQuickAction)
        case field(ContactField)
    }

    private func focusTarget(at selection: Int) -> FocusTarget? {
        guard let stop = session.focus.stop, let card = card(at: selection) else { return nil }
        if card.hasQuickRow, stop == 0 {
            let actions = card.quickActions
            return actions.indices.contains(session.focus.button)
                ? .quick(actions[session.focus.button]) : nil
        }
        return card.field(atStop: stop).map { .field($0) }
    }

    // MARK: - Keyboard

    /// ⇥ walks into the card and through its stops; past the last it returns to the list.
    func tab(at selection: Int, backwards: Bool) -> Bool {
        guard let card = card(at: selection) else { return false }
        if session.focus.isInCard {
            session.updateFocus { $0.tab(backwards: backwards, stops: card.stopCount) }
            return true
        }
        guard !backwards else { return false }
        session.updateFocus { $0.enter(stops: card.stopCount) }
        return session.focus.isInCard
    }

    /// ↑/↓ step through the card's stops; → on an empty query steps in, else the caret keeps it.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        guard let card = card(at: selection) else { return nil }
        if session.focus.isInCard {
            let onQuickRow = card.hasQuickRow && session.focus.stop == 0
            let buttons = card.quickActions.count
            session.updateFocus {
                switch axis {
                case .vertical: $0.moveVertically(delta, stops: card.stopCount)
                case .horizontal:
                    $0.moveHorizontally(delta, onQuickRow: onQuickRow, buttons: buttons)
                }
            }
            return selection
        }
        guard axis == .horizontal, delta > 0, session.query.isEmpty else { return nil }
        session.updateFocus { $0.enter(stops: card.stopCount) }
        return session.focus.isInCard ? selection : nil
    }

    func escape(at selection: Int) -> Bool {
        guard session.focus.isInCard else { return false }
        session.updateFocus { $0.leave() }
        return true
    }

    func hasPrimaryAction(at selection: Int) -> Bool { contact(at: selection) != nil }

    func activate(at selection: Int) {
        guard let contact = contact(at: selection) else { return }
        switch focusTarget(at: selection) {
        case .quick(let action): coordinator.perform(action, on: contact)
        case .field(let field): coordinator.performPrimary(field)
        case nil: coordinator.openInContacts(contact)
        }
    }

    /// ⌘↵ — the focused value, else the name, for pasting into a message or a document.
    func secondary(at selection: Int) -> Bool {
        guard let contact = contact(at: selection) else { return false }
        if case .field(let field) = focusTarget(at: selection) {
            coordinator.copyInCard(field.value, id: field.id)
            return true
        }
        coordinator.copy(contact.displayName, message: String(localized: "Copied name"))
        return true
    }

    // MARK: - Actions

    /// A card with several numbers gets a row per number, each stating its label and value.
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let contact = contact(at: selection) else { return nil }
        if case .field(let field) = focusTarget(at: selection) {
            return PopoverMenuContent(header: contact.displayName, items: fieldItems(field, contact))
        }
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

    private func fieldItems(_ field: ContactField, _ contact: Contact) -> [PopoverMenuItem] {
        let copy = PopoverMenuItem(
            title: field.copyTitle, systemImage: "doc.on.doc",
            shortcut: field.kind == .birthday ? "↵" : "⌘↵"
        ) { coordinator.copyInCard(field.value, id: field.id) }
        let primary = PopoverMenuItem(
            title: field.primaryTitle, systemImage: field.primarySymbol, shortcut: "↵"
        ) { coordinator.performPrimary(field) }
        switch field.kind {
        case .phone:
            return [
                primary,
                PopoverMenuItem(title: String(localized: "FaceTime"), systemImage: "video") {
                    coordinator.open(ContactFormat.faceTimeURL(field.value))
                },
                PopoverMenuItem(title: String(localized: "Call"), systemImage: "phone") {
                    coordinator.open(ContactFormat.callURL(field.value))
                },
                copy
            ]
        case .birthday: return [copy]
        case .email, .address: return [primary, copy]
        }
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
                onSelect: {
                    session.updateFocus { $0.leave() }
                    vm.selection = $0
                },
                onActivate: { activate(at: vm.selection) },
                onActions: { index in
                    vm.selection = index
                    openActions()
                },
                onFocusStop: { stop in
                    guard let card = card(at: vm.selection) else { return }
                    session.updateFocus { $0.focus(stop: stop, stops: card.stopCount) }
                },
                onQuick: { action in
                    guard let contact = contact(at: vm.selection) else { return }
                    coordinator.perform(action, on: contact)
                },
                onPrimary: { coordinator.performPrimary($0) },
                onCopy: { coordinator.copyInCard($0.value, id: $0.id) }
            )
            .onChange(of: selection) { session.updateFocus { $0.leave() } }
            .onAppear { session.start(query: vm.query) }
            .onDisappear { session.end() }
            .onChange(of: vm.query) { _, query in session.setQuery(query) })
    }
}
