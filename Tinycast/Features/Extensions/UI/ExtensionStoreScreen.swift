import AppKit
import SwiftUI

/// Browse, search, install, update and uninstall Raycast Store extensions without leaving the palette.
struct ExtensionStoreScreen: PaletteScreen {
    typealias Entry = ExtensionStoreSession.Entry

    let session: ExtensionStoreSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void
    let openArgumentOptions: (String) -> Void

    private static let filterField = "filter"
    private static let filterWidth: CGFloat = 132

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    var rows: [Entry] { session.entries }

    /// The pill carries no selection, so the screen applies the clamp the palette applies.
    private var clampedSelection: Int {
        let count = rows.count
        return count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    private func entry(at selection: Int) -> Entry? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    // MARK: - Primary action

    var primaryActionTitle: String {
        guard let entry = entry(at: clampedSelection) else { return String(localized: "Install") }
        switch session.state(for: entry) {
        case .available: return String(localized: "Install")
        case .installing: return String(localized: "Installing…")
        case .installed: return String(localized: "Open")
        case .updateAvailable: return String(localized: "Update")
        case .updating: return String(localized: "Updating…")
        }
    }

    func hasPrimaryAction(at selection: Int) -> Bool { entry(at: selection) != nil }

    func isPrimaryActionEnabled(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        switch session.state(for: entry) {
        case .available: return entry.listing != nil
        case .installed, .updateAvailable: return true
        case .installing, .updating: return false
        }
    }

    func activate(at selection: Int) {
        guard let entry = entry(at: selection), isPrimaryActionEnabled(at: selection) else { return }
        switch session.state(for: entry) {
        case .available: session.install(entry)
        case .updateAvailable: session.update(entry)
        case .installed: open(entry)
        case .installing, .updating: break
        }
    }

    /// ⌘↵ opens the extension's page on raycast.com.
    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection), entry.pageURL != nil else { return false }
        openInBrowser(entry)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete, .delete:
            guard let entry = entry(at: selection), session.installedExtension(for: entry) != nil else {
                return false
            }
            uninstall(entry)
        case .copyPath:
            guard let entry = entry(at: selection), entry.pageURL != nil else { return false }
            copyLink(entry)
        case .restart:
            session.retry()
        default:
            return false
        }
        return true
    }

    // MARK: - Actions

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection) else { return nil }
        let state = session.state(for: entry)
        var items: [PopoverMenuItem] = []
        switch state {
        case .available:
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Install"), systemImage: "arrow.down.circle",
                    isEnabled: entry.listing != nil, shortcut: "↵"
                ) { session.install(entry) })
        case .installing, .updating:
            items.append(
                PopoverMenuItem(
                    title: state == .updating
                        ? String(localized: "Updating…") : String(localized: "Installing…"),
                    systemImage: "arrow.down.circle", isLoading: true
                ) {})
        case .updateAvailable:
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Update"), systemImage: "arrow.triangle.2.circlepath",
                    shortcut: "↵"
                ) { session.update(entry) })
            items.append(openItem(entry, shortcut: nil))
        case .installed:
            items.append(openItem(entry, shortcut: "↵"))
        }
        if state == .installed || state == .updateAvailable {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Uninstall"), systemImage: "trash", startsSection: true,
                    shortcut: "⌃X", isDestructive: true
                ) { uninstall(entry) })
        }
        if entry.pageURL != nil {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Open in Browser"), systemImage: "safari",
                    startsSection: true, shortcut: "⌘↵"
                ) { openInBrowser(entry) })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy Link"), systemImage: "link", shortcut: "⌃⌘C"
                ) { copyLink(entry) })
        }
        return PopoverMenuContent(header: entry.title, items: items)
    }

    private func openItem(_ entry: Entry, shortcut: String?) -> PopoverMenuItem {
        PopoverMenuItem(
            title: String(localized: "Open"), systemImage: "puzzlepiece.extension", shortcut: shortcut
        ) { open(entry) }
    }

    /// Opens the extension's page in Settings, where its commands and preferences live.
    private func open(_ entry: Entry) {
        guard let owner = session.installedExtension(for: entry) else { return }
        core.extensionCoordinator.showExtensionSettings(for: owner)
    }

    private func uninstall(_ entry: Entry) {
        guard let owner = session.installedExtension(for: entry) else { return }
        core.extensionCoordinator.confirmUninstall(owner)
    }

    private func openInBrowser(_ entry: Entry) {
        guard let url = entry.pageURL else { return }
        NSWorkspace.shared.open(url)
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    private func copyLink(_ entry: Entry) {
        guard let url = entry.pageURL else { return }
        guard Paster.copyPlainText(url.absoluteString) else {
            core.showMessage(String(localized: "Couldn’t copy link"), tone: .danger)
            return
        }
        core.showMessage(String(localized: "Link copied"))
    }

    // MARK: - Filter

    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        PaletteHeaderAccessory(
            width: metrics.scaled(Self.filterWidth), fieldNames: [], firstIncompleteField: nil,
            optionsMenu: { field in field == Self.filterField ? filterMenu : nil },
            placement: .besideSearchField,
            view: AnyView(
                HeaderMenuButton(
                    title: session.filter.title, systemImage: session.filter.systemImage,
                    isOpen: false, help: String(localized: "Filter extensions"),
                    action: { openArgumentOptions(Self.filterField) })))
    }

    private var filterMenu: PopoverMenuContent {
        PopoverMenuContent(
            header: nil,
            items: ExtensionStoreSession.Filter.allCases.map { filter in
                PopoverMenuItem(
                    title: filter.title, icon: session.filter == filter ? .symbol("checkmark") : .blank
                ) { session.setFilter(filter) }
            })
    }

    // MARK: - Body

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            ExtensionStoreView(
                session: session, rows: rows, selection: selection, scroll: scroll,
                onSelect: { vm.selection = $0 },
                onActivate: { activate(at: vm.selection) },
                onActions: { index in
                    vm.selection = index
                    openActions()
                }
            )
            .onAppear {
                session.setQuery(vm.query)
                session.start()
            }
            .onDisappear { session.end() }
            .onChange(of: vm.query) { _, query in session.setQuery(query) })
    }
}
