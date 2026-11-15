import SwiftUI

/// The contact list and the selected card's page; row order comes from the screen.
struct ContactsView: View {
    @Environment(\.metrics) private var metrics
    let session: ContactsSession
    let rows: [Contact]
    let selection: Int
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void
    let onFocusStop: (Int) -> Void
    let onQuick: (ContactQuickAction) -> Void
    let primaryAction: (ContactField) -> ContactAction
    let onPrimary: (ContactField) -> Void
    let onCopy: (ContactField) -> Void
    let commandHint: String

    private var selected: Contact? { rows.indices.contains(selection) ? rows[selection] : nil }

    var body: some View {
        if rows.isEmpty {
            EmptyResults(text: emptyMessage, systemImage: "person.crop.circle")
        } else {
            HStack(spacing: 0) {
                list.frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                ContactDetailPane(
                    session: session, contact: selected, onFocusStop: onFocusStop, onQuick: onQuick,
                    primaryAction: primaryAction, onPrimary: onPrimary, onCopy: onCopy,
                    commandHint: commandHint)
            }
        }
    }

    /// Names why the list is empty: no access reads very differently from no match.
    private var emptyMessage: String {
        if session.store.access != .granted {
            return String(localized: "Tinycast has no access to your contacts")
        }
        if session.phase == .loading { return String(localized: "Loading…") }
        return session.query.isEmpty
            ? String(localized: "No contacts") : String(localized: "No matching contacts")
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, contact in
                        ContactRow(session: session, contact: contact, selected: index == selection)
                            .contentShape(Rectangle())
                            .onRightClick { onActions(index) }
                            .onRowClick(
                                select: { onSelect(index) },
                                activate: {
                                    onSelect(index)
                                    onActivate()
                                }
                            )
                            .selectionFrame(index == selection)
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selected?.id, atOrigin: selection == 0, proxy: proxy)
        }
    }
}

private struct ContactRow: View {
    @Environment(\.metrics) private var metrics
    let session: ContactsSession
    let contact: Contact
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            ContactAvatar(
                contact: contact, size: metrics.size.resultRowIcon,
                photo: session.thumbnails[contact.id], decorative: true)
            VStack(alignment: .leading, spacing: 0) {
                Text(contact.displayName)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                if !contact.subtitle.isEmpty {
                    Text(contact.subtitle)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: metrics.spacing.sm)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
        .task(id: contact.id) { await session.loadThumbnail(for: contact.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The card's photo, or a monogram in the name's own hue when it has none.
struct ContactAvatar: View {
    let contact: Contact
    let size: CGFloat
    /// A full-size photo, once loaded; until then the list's thumbnail stands in at the same size.
    var photo: Data?
    /// True where the name is read out beside it, so VoiceOver does not say it twice.
    var decorative = false

    var body: some View {
        Group {
            if let data = photo ?? contact.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(contact.initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.monogramInk)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.monogram(hue: contact.monogramHue))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.Colors.separator, lineWidth: Theme.Size.hairline))
        .accessibilityHidden(decorative)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(contact.displayName))
        .accessibilityAddTraits(.isImage)
    }
}

/// One card's values, grouped the way Contacts shows them, with the keyboard's stops marked.
struct ContactDetailPane: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: ContactsSession
    let contact: Contact?
    let onFocusStop: (Int) -> Void
    let onQuick: (ContactQuickAction) -> Void
    let primaryAction: (ContactField) -> ContactAction
    let onPrimary: (ContactField) -> Void
    let onCopy: (ContactField) -> Void
    let commandHint: String

    private static let photoSide: CGFloat = 104
    private static let photoPixels = 640
    private static let quickRowID = "quick-actions"

    private var shown: Contact? { contact.map(session.resolved) }

    private var fade: Animation? { reduceMotion ? nil : .easeOut(duration: Theme.Duration.hover) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let contact = shown {
                    content(ContactCard(contact))
                        .id(contact.id)
                        .transition(.opacity)
                }
            }
            .animation(fade, value: contact?.id)
            .onChange(of: session.focus) { _, focus in
                guard let contact = shown, let stop = focus.stop else { return }
                let card = ContactCard(contact)
                let target =
                    card.hasQuickRow && stop == 0
                    ? Self.quickRowID : card.field(atStop: stop)?.id
                guard let target else { return }
                withAnimation(fade) { proxy.scrollTo(target) }
            }
        }
        .frame(maxWidth: .infinity)
        .edgeDissolve()
        .thinScrollbar()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.focus.isInCard { keyHints }
        }
        .animation(fade, value: session.focus.isInCard)
        .task(id: contact?.id) {
            guard let id = contact?.id else { return }
            await session.loadDetail(for: id)
            await session.photo(for: id, maxPixel: Self.photoPixels)
        }
    }

    private func content(_ card: ContactCard) -> some View {
        VStack(spacing: 0) {
            header(card.contact)
            if card.hasQuickRow {
                quickRow(card).padding(.top, metrics.spacing.xxl)
            }
            VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
                section(String(localized: "Phone"), card, .phone)
                section(String(localized: "Email"), card, .email)
                section(String(localized: "Address"), card, .address)
                section(String(localized: "Birthday"), card, .birthday)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, metrics.spacing.xxl)
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xl)
        .hideNativeScrollers()
    }

    // MARK: - Header

    private func header(_ contact: Contact) -> some View {
        VStack(spacing: metrics.spacing.sm) {
            ContactAvatar(
                contact: contact, size: metrics.scaled(Self.photoSide),
                photo: session.photos[contact.id])
            Text(contact.displayName)
                .font(metrics.typography.calcResult.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.top, metrics.spacing.md)
            if !contact.subtitle.isEmpty {
                Text(contact.subtitle)
                    .font(metrics.typography.rowTitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Quick actions

    private func quickRow(_ card: ContactCard) -> some View {
        HStack(spacing: metrics.spacing.xxl) {
            ForEach(Array(card.quickActions.enumerated()), id: \.element) { index, action in
                QuickActionButton(
                    action: action,
                    focused: session.focus.stop == 0 && session.focus.button == index,
                    perform: { onQuick(action) })
            }
        }
        .frame(maxWidth: .infinity)
        .id(Self.quickRowID)
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(_ title: String, _ card: ContactCard, _ kind: ContactField.Kind)
        -> some View
    {
        let fields = card.fields.filter { $0.kind == kind }
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text(title)
                    .font(metrics.typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, metrics.spacing.md)
                ForEach(fields) { field in
                    let stop = card.stop(of: field)
                    FieldRow(
                        field: field, primary: primaryAction(field),
                        focused: stop != nil && session.focus.stop == stop,
                        copied: session.copiedID == field.id,
                        focus: { stop.map(onFocusStop) }, perform: { onPrimary(field) },
                        copy: { onCopy(field) })
                    .id(field.id)
                }
            }
        }
    }

    // MARK: - Key hints

    private var keyHints: some View {
        HStack(spacing: metrics.spacing.xl) {
            hint(["↑", "↓"], String(localized: "Move"))
            hint(["←"], String(localized: "List"))
            hint(["⌘", "↵"], commandHint)
        }
        .padding(.vertical, metrics.spacing.sm)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
        .accessibilityHidden(true)
    }

    private func hint(_ caps: [String], _ title: String) -> some View {
        HStack(spacing: metrics.spacing.sm) {
            HStack(spacing: metrics.spacing.xxs) {
                ForEach(caps, id: \.self) { KeyCapChip(text: $0, style: .outline) }
            }
            Text(title)
                .font(metrics.typography.bar)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

/// A compact round button for the card's most common hand-offs.
private struct QuickActionButton: View {
    @Environment(\.metrics) private var metrics
    let action: ContactQuickAction
    let focused: Bool
    let perform: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: perform) {
            VStack(spacing: metrics.spacing.xs) {
                Image(systemName: action.symbol)
                    .font(metrics.typography.menuIcon)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: metrics.size.menuButton, height: metrics.size.menuButton)
                    .background(Circle().fill(fill))
                    .overlay {
                        Circle().strokeBorder(
                            focused ? Theme.Colors.border : .clear,
                            lineWidth: metrics.size.formFieldFocusStroke)
                    }
                Text(action.title)
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .armedHover($hovered)
        .accessibilityLabel(Text(action.title))
    }

    private var fill: Color {
        if focused { return Theme.Colors.controlPressed }
        return hovered ? Theme.Colors.controlHover : Theme.Colors.controlSurface
    }
}

/// One value: label small and quiet, value prominent, and copy revealed on hover or focus.
private struct FieldRow: View {
    @Environment(\.metrics) private var metrics
    let field: ContactField
    /// What ↵ does here, which decides the first hover button; copy is always the other.
    let primary: ContactAction
    let focused: Bool
    let copied: Bool
    let focus: () -> Void
    let perform: () -> Void
    let copy: () -> Void
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
        HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                if !field.label.isEmpty {
                    Text(field.label)
                        .font(metrics.typography.rowTrailing)
                        .textScale(.secondary)
                        .foregroundStyle(.secondary)
                }
                Text(field.value)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: metrics.spacing.sm)
            trailing
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(shape.fill(fill))
        .overlay {
            shape.strokeBorder(
                focused ? Theme.Colors.border : .clear,
                lineWidth: metrics.size.formFieldFocusStroke)
        }
        .contentShape(shape)
        .onTapGesture(perform: focus)
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(primary.title(for: field.kind)), perform)
        .accessibilityAction(named: Text(ContactAction.copy.title(for: field.kind)), copy)
    }

    private var fill: Color {
        if focused { return Theme.Colors.selection }
        return hovered ? Theme.Colors.rowHover : .clear
    }

    /// Both states always take their space and only fade, so no text moves when one appears.
    private var trailing: some View {
        let showButtons = (focused || hovered) && !copied
        return ZStack(alignment: .trailing) {
            HStack(spacing: metrics.spacing.xs) {
                if primary != .copy {
                    iconButton(primary.symbol, primary.title(for: field.kind), perform)
                }
                iconButton("doc.on.doc", ContactAction.copy.title(for: field.kind), copy)
            }
            .opacity(showButtons ? 1 : 0)
            .allowsHitTesting(showButtons)
            .accessibilityHidden(!showButtons)
            Label("Copied", systemImage: "checkmark")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .opacity(copied ? 1 : 0)
                .accessibilityHidden(!copied)
        }
        .fixedSize()
    }

    private func iconButton(_ symbol: String, _ title: String, _ action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .frame(width: metrics.size.rowIcon * 0.8, height: metrics.size.rowIcon * 0.8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(title)
        .accessibilityLabel(Text(title))
    }
}
