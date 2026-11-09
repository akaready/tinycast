import SwiftUI

/// The Store's list and the selected extension's page; row order comes from the screen.
struct ExtensionStoreView: View {
    typealias Entry = ExtensionStoreSession.Entry

    @Environment(\.metrics) private var metrics
    let session: ExtensionStoreSession
    let rows: [Entry]
    let selection: Int
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void
    let onCategory: (String) -> Void

    private var selected: Entry? { rows.indices.contains(selection) ? rows[selection] : nil }

    private struct SelectionKey: Equatable {
        let id: String?
        let index: Int
        let count: Int
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    list.frame(width: metrics.size.clipboardListWidth)
                    Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                    ExtensionStoreDetailPane(
                        entry: selected, state: selected.map(session.state(for:)),
                        detail: selected.flatMap { session.details[$0.key] },
                        readme: selected.flatMap { session.readmes[$0.key] },
                        failure: selected.flatMap { session.failures[$0.id] },
                        onCategory: onCategory)
                }
            }
        }
        .task(id: SelectionKey(id: selected?.id, index: selection, count: rows.count)) {
            session.select(selected)
            session.loadNextPageIfNeeded(nearIndex: selection)
        }
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyState: some View {
        switch session.filter {
        case .all:
            switch session.phase {
            case .idle, .loading:
                EmptyResults(text: String(localized: "Loading…"), systemImage: "puzzlepiece.extension")
            case .failed(let message):
                EmptyResults(
                    text: String(localized: "Couldn’t reach the Store"),
                    detail: message + "\n" + String(localized: "Press ⌘R to try again."),
                    systemImage: "wifi.exclamationmark")
            case .loaded:
                EmptyResults(
                    text: session.query.isEmpty
                        ? String(localized: "No extensions")
                        : String(localized: "No extensions match “\(session.query)”"),
                    systemImage: "puzzlepiece.extension")
            }
        case .installed:
            EmptyResults(
                text: session.query.isEmpty
                    ? String(localized: "No extensions installed")
                    : String(localized: "No matching installed extensions"),
                systemImage: "puzzlepiece.extension")
        case .updates:
            EmptyResults(
                text: String(localized: "Everything is up to date"), systemImage: "checkmark.circle")
        case .raycast:
            EmptyResults(
                text: session.raycastAvailable
                    ? String(localized: "Nothing to Import")
                    : String(localized: "No Raycast install found in ~/.config."),
                systemImage: "arrow.down.doc")
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if session.pendingUpdateCount > 0 { ExtensionStoreUpdatesBanner(session: session) }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        ExtensionStoreRow(
                            entry: entry, state: session.state(for: entry),
                            selected: index == selection
                        )
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
                        .onAppear { session.loadNextPageIfNeeded(nearIndex: index) }
                    }
                    if session.isLoadingMore {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, metrics.spacing.md)
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

private struct ExtensionStoreRow: View {
    @Environment(\.metrics) private var metrics
    let entry: ExtensionStoreSession.Entry
    let state: ExtensionStoreSession.InstallState
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            ExtensionStoreIcon(entry: entry, size: metrics.size.resultRowIcon)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                facts
            }
            .layoutPriority(1)
            Spacer(minLength: metrics.spacing.sm)
            trailing
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }

    private var facts: some View {
        HStack(spacing: metrics.spacing.xs) {
            Text(entry.author).lineLimit(1)
            if let downloads = entry.downloadCount, downloads > 0 {
                Image(systemName: "arrow.down.circle").imageScale(.small)
                Text(ExtensionListing.abbreviate(downloads)).fixedSize()
            }
        }
        .font(metrics.typography.rowTrailing)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .available:
            EmptyView()
        case .installing, .updating:
            ProgressView().controlSize(.small)
        case .installed:
            ExtensionStoreTag(text: String(localized: "Installed"), color: Theme.Colors.success)
        case .updateAvailable:
            ExtensionStoreTag(text: String(localized: "Update"), color: Theme.Colors.primaryAction)
        }
    }
}

/// Not a row: ↑/↓ never land on it, so ↵ can't update everything by accident.
private struct ExtensionStoreUpdatesBanner: View {
    @Environment(\.metrics) private var metrics
    let session: ExtensionStoreSession

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            HStack(spacing: metrics.spacing.lg) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Theme.Colors.primaryAction)
                Text("\(session.pendingUpdateCount) updates available")
                    .font(metrics.typography.rowTrailing)
                    .lineLimit(1)
                Spacer(minLength: metrics.spacing.sm)
                if session.isUpdating {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Update All") { session.updateAll() }
                        .buttonStyle(.plain)
                        .font(metrics.typography.bar)
                        .foregroundStyle(Theme.Colors.primaryAction)
                }
            }
            if let error = session.updateError {
                Text(error)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .padding(.bottom, metrics.spacing.xs)
    }
}

struct ExtensionStoreTag: View {
    @Environment(\.metrics) private var metrics
    let text: String
    var color = Theme.Colors.textSecondary

    var body: some View {
        Text(text)
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(color)
            .padding(.horizontal, metrics.spacing.xs)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.glyph * 2, style: .continuous)
                    .fill(color.opacity(0.16))
            )
            .lineLimit(1)
    }
}

struct ExtensionStoreIcon: View {
    @Environment(\.isDarkAppearance) private var isDark
    let entry: ExtensionStoreSession.Entry
    let size: CGFloat

    private var resolved: ExtensionImage.Resolved {
        if case .github = entry.kind {
            return ExtensionImage.Resolved(source: .symbol("hammer"))
        }
        if let url = entry.listing?.iconURL(isDark: isDark) {
            return ExtensionImage.Resolved(source: .remote(url))
        }
        if let path = (entry.installed ?? entry.raycastCopy)?.iconPath {
            return ExtensionImage.Resolved(source: .file(path))
        }
        return ExtensionImage.Resolved(source: .symbol("puzzlepiece.extension"))
    }

    var body: some View {
        ExtensionIconView(resolved: resolved, size: size)
    }
}
