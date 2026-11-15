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

    private var selected: Contact? { rows.indices.contains(selection) ? rows[selection] : nil }

    var body: some View {
        if rows.isEmpty {
            EmptyResults(text: emptyMessage, systemImage: "person.crop.circle")
        } else {
            HStack(spacing: 0) {
                list.frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                ContactDetailPane(contact: selected)
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
                        ContactRow(contact: contact, selected: index == selection)
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
            ContactAvatar(contact: contact, size: metrics.size.resultRowIcon)
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The card's photo, or its initials when it has none.
struct ContactAvatar: View {
    @Environment(\.metrics) private var metrics
    let contact: Contact
    let size: CGFloat

    var body: some View {
        Group {
            if let data = contact.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(contact.initials)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.controlSurface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// One card's values, grouped the way Contacts shows them.
struct ContactDetailPane: View {
    @Environment(\.metrics) private var metrics
    let contact: Contact?

    private static let avatarSide: CGFloat = 56

    var body: some View {
        ScrollView {
            if let contact {
                VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
                    header(contact)
                    group(String(localized: "Phone"), contact.phones)
                    group(String(localized: "Email"), contact.emails)
                    group(String(localized: "Address"), contact.addresses)
                    birthday(contact)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.spacing.xl)
                .padding(.vertical, metrics.spacing.md)
                .hideNativeScrollers()
            }
        }
        .frame(maxWidth: .infinity)
        .edgeDissolve()
        .thinScrollbar()
    }

    private func header(_ contact: Contact) -> some View {
        HStack(alignment: .center, spacing: metrics.spacing.xl) {
            ContactAvatar(contact: contact, size: metrics.scaled(Self.avatarSide))
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text(contact.displayName).font(metrics.typography.panelTitle)
                if !contact.subtitle.isEmpty {
                    Text(contact.subtitle)
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ entries: [Contact.Entry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                Text(title)
                    .font(metrics.typography.sectionHeader)
                    .foregroundStyle(.secondary)
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 0) {
                        if !entry.label.isEmpty {
                            Text(entry.label)
                                .font(metrics.typography.rowTrailing)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.value).font(metrics.typography.rowTitle)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func birthday(_ contact: Contact) -> some View {
        if let components = contact.birthday,
            let text = ContactFormat.birthday(components, calendar: .current, locale: .current)
        {
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                Text("Birthday")
                    .font(metrics.typography.sectionHeader)
                    .foregroundStyle(.secondary)
                Text(text).font(metrics.typography.rowTitle)
            }
        }
    }
}
