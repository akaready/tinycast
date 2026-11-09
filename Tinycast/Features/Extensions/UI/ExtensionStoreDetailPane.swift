import SwiftUI

/// One extension's page: header, screenshots, commands, what's new, and the README.
struct ExtensionStoreDetailPane: View {
    typealias Entry = ExtensionStoreSession.Entry

    @Environment(\.metrics) private var metrics
    let entry: Entry?
    let state: ExtensionStoreSession.InstallState?
    let detail: ExtensionStoreSession.Fetch<ExtensionStoreDetail>?
    let readme: ExtensionStoreSession.Fetch<String>?
    let failure: String?

    private static let iconSide: CGFloat = 48
    private static let shotHeight: CGFloat = 150
    private static let shownCommands = 10

    private var loaded: ExtensionStoreDetail? {
        if case .loaded(let detail)? = detail { return detail }
        return nil
    }

    var body: some View {
        ScrollView {
            if let entry {
                VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
                    header(entry)
                    sections(entry)
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

    // MARK: - Header

    private func header(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            HStack(alignment: .top, spacing: metrics.spacing.xl) {
                ExtensionStoreIcon(entry: entry, size: metrics.scaled(Self.iconSide))
                VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                    Text(entry.title)
                        .font(metrics.typography.panelTitle)
                    if !entry.author.isEmpty {
                        Text(entry.author)
                            .font(metrics.typography.rowTitle)
                            .foregroundStyle(.secondary)
                    }
                    facts(entry)
                }
            }
            if !entry.summary.isEmpty {
                Text(entry.summary).font(metrics.typography.rowTitle)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.orange)
            }
            let categories = loaded?.listing.categories ?? entry.listing?.categories ?? []
            if !categories.isEmpty {
                FlowLayout(spacing: metrics.spacing.sm) {
                    ForEach(categories, id: \.self) { ExtensionStoreTag(text: $0) }
                }
            }
        }
    }

    private func facts(_ entry: Entry) -> some View {
        let listing = loaded?.listing ?? entry.listing
        return HStack(spacing: metrics.spacing.xl) {
            if let downloads = listing?.downloadCount, downloads > 0 {
                Label(
                    String(localized: "\(downloads.formatted()) installs"),
                    systemImage: "arrow.down.circle")
            }
            if let updated = listing?.updatedAt {
                Label(
                    String(localized: "Updated \(updated.formatted(.relative(presentation: .named)))"),
                    systemImage: "clock")
            }
            if state == .installed || state == .updateAvailable {
                Label(String(localized: "Installed"), systemImage: "checkmark.circle")
            }
        }
        .font(metrics.typography.rowTrailing)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sections(_ entry: Entry) -> some View {
        if case .github = entry.kind {
            note(
                String(
                    localized: """
                        Installing runs your package manager and the extension's own build script. \
                        Install only from someone you trust.
                        """))
        } else {
            storeSections
        }
    }

    @ViewBuilder
    private var storeSections: some View {
        switch detail {
        case nil, .loading?:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        case .unavailable?:
            note(String(localized: "This extension has no page in the Store."))
        case .failed(let message)?:
            note(message + "\n" + String(localized: "Press ⌘R to try again."))
        case .loaded(let detail)?:
            screenshots(detail.screenshots)
            commands(detail.commands)
            if let release = detail.changelog.first { whatsNew(release) }
            readmeSection
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(.secondary)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func screenshots(_ urls: [URL]) -> some View {
        if !urls.isEmpty {
            ScrollView(.horizontal) {
                LazyHStack(spacing: metrics.spacing.md) {
                    ForEach(urls, id: \.self) {
                        ExtensionStoreShot(url: $0, height: metrics.scaled(Self.shotHeight))
                    }
                }
                .hideNativeScrollers()
            }
            .hideNativeScrollers()
            .frame(height: metrics.scaled(Self.shotHeight))
        }
    }

    @ViewBuilder
    private func commands(_ commands: [ExtensionStoreDetail.Command]) -> some View {
        if !commands.isEmpty {
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                title(String(localized: "Commands"))
                ForEach(commands.prefix(Self.shownCommands)) { command in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(command.title).font(metrics.typography.rowTitle)
                        if !command.summary.isEmpty {
                            Text(command.summary)
                                .font(metrics.typography.rowTrailing)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if commands.count > Self.shownCommands {
                    note(String(localized: "and \(commands.count - Self.shownCommands) more"))
                }
            }
        }
    }

    private func whatsNew(_ release: ExtensionStoreDetail.Release) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            title(String(localized: "What’s New"))
            HStack(spacing: metrics.spacing.md) {
                if !release.title.isEmpty {
                    Text(release.title).font(metrics.typography.rowTitle).fontWeight(.semibold)
                }
                if let date = release.date {
                    Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)))
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.secondary)
                }
            }
            if !release.markdown.isEmpty { ExtensionMarkdownView(markdown: release.markdown) }
        }
    }

    @ViewBuilder
    private var readmeSection: some View {
        switch readme {
        case nil, .unavailable?:
            EmptyView()
        case .loading?:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        case .failed(let message)?:
            note(message)
        case .loaded(let text)?:
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                title(String(localized: "README"))
                ExtensionMarkdownView(markdown: text)
            }
        }
    }
}

/// One screenshot, fetched and downsampled only while its page is the one open.
private struct ExtensionStoreShot: View {
    @Environment(\.metrics) private var metrics
    let url: URL
    let height: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Rectangle().fill(Theme.Colors.iconPlaceholder).frame(width: height * 1.6)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
        .task(id: url) { image = await ExtensionStoreScreenshot.load(url) }
    }
}
