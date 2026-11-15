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
        case .field(let field):
            coordinator.action(for: ContactTarget(field.kind), command: false).title(for: field.kind)
        case nil: coordinator.action(for: .contact, command: false).title(for: nil)
        }
    }

    private func contact(at selection: Int) -> Contact? {
        let rows = rows
        return rows.indices.contains(selection) ? session.resolved(rows[selection]) : nil
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

    /// The word beside ⌘↵ in the card's key hints: what the focused stop's command-return does.
    private func commandHint(at selection: Int) -> String {
        switch focusTarget(at: selection) {
        case .field(let field):
            return coordinator.action(for: ContactTarget(field.kind), command: true).hint
        default: return coordinator.action(for: .contact, command: true).hint
        }
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
        case .field(let field):
            let target = ContactTarget(field.kind)
            coordinator.run(coordinator.action(for: target, command: false), field: field, contact: contact)
        case nil:
            coordinator.run(coordinator.action(for: .contact, command: false), field: nil, contact: contact)
        }
    }

    /// ⌘↵ — by default the focused value, else the name; Settings can point it elsewhere.
    func secondary(at selection: Int) -> Bool {
        guard let contact = contact(at: selection) else { return false }
        if case .field(let field) = focusTarget(at: selection) {
            let target = ContactTarget(field.kind)
            coordinator.run(coordinator.action(for: target, command: true), field: field, contact: contact)
        } else {
            coordinator.run(coordinator.action(for: .contact, command: true), field: nil, contact: contact)
        }
        return true
    }

    // MARK: - Actions

    /// Every action stays in the menu whatever Settings binds ↵ and ⌘↵ to; the bound ones say so.
    private func shortcut(_ action: ContactAction, _ target: ContactTarget) -> String? {
        if action == coordinator.action(for: target, command: false) { return "↵" }
        return action == coordinator.action(for: target, command: true) ? "⌘↵" : nil
    }

    /// A card with several values gets a row per value, each stating its label and value.
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let contact = contact(at: selection) else { return nil }
        if case .field(let field) = focusTarget(at: selection) {
            return PopoverMenuContent(header: contact.displayName, items: fieldItems(field, contact))
        }
        var items = ContactTarget.contact.actions.map { action in
            PopoverMenuItem(
                title: action.title(for: nil), systemImage: action.symbol,
                shortcut: shortcut(action, .contact)
            ) { coordinator.run(action, field: nil, contact: contact) }
        }
        let fields = ContactCard(contact).fields
        for kind in [ContactField.Kind.phone, .email, .address] {
            let ofKind = fields.filter { $0.kind == kind }
            for field in ofKind {
                for action in ContactTarget(kind).actions {
                    items.append(
                        row(action, field, contact, first: action == ContactTarget(kind).actions.first
                            && field == ofKind.first))
                }
            }
        }
        return PopoverMenuContent(header: contact.displayName, items: items)
    }

    private func fieldItems(_ field: ContactField, _ contact: Contact) -> [PopoverMenuItem] {
        let target = ContactTarget(field.kind)
        return target.actions.map { action in
            PopoverMenuItem(
                title: action.title(for: field.kind), systemImage: action.symbol,
                shortcut: shortcut(action, target)
            ) { coordinator.run(action, field: field, contact: contact) }
        }
    }

    private func row(
        _ action: ContactAction, _ field: ContactField, _ contact: Contact, first: Bool
    ) -> PopoverMenuItem {
        let detail = [field.label, ContactFormat.oneLine(field.value)].filter { !$0.isEmpty }
            .joined(separator: "  ")
        return PopoverMenuItem(
            title: action.title(for: field.kind), icon: .symbol(action.symbol), startsSection: first,
            detail: detail
        ) { coordinator.run(action, field: field, contact: contact) }
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
                primaryAction: { coordinator.action(for: ContactTarget($0.kind), command: false) },
                onPrimary: {
                    guard let contact = contact(at: vm.selection) else { return }
                    coordinator.run(
                        coordinator.action(for: ContactTarget($0.kind), command: false),
                        field: $0, contact: contact)
                },
                onCopy: { coordinator.copyInCard($0.value, id: $0.id) },
                commandHint: commandHint(at: selection)
            )
            .onChange(of: selection) { session.updateFocus { $0.leave() } }
            .onAppear { session.start(query: vm.query) }
            .onDisappear { session.end() }
            .onChange(of: vm.query) { _, query in session.setQuery(query) })
    }
}
