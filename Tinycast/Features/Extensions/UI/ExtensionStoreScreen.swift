import AppKit
import SwiftUI

/// Browse, search, install, update and uninstall Raycast Store extensions in the palette.
struct ExtensionStoreScreen: PaletteScreen {
    typealias Entry = ExtensionStoreSession.Entry

    let session: ExtensionStoreSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void
    let openArgumentOptions: (String) -> Void

    static let filterField = "filter"

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

    /// With no row to act on, the pill still checks for updates, so ⌘K never has nothing to open.
    var actsWithoutRows: Bool { true }

    /// Row 0 may be the GitHub pseudo-row, which builds code, so the highlight lands past it.
    var landingSelection: Int {
        guard case .github? = rows.first?.kind, rows.count > 1 else { return 0 }
        return 1
    }

    var primaryActionTitle: String {
        guard let entry = entry(at: clampedSelection) else {
            return String(localized: "Check for Updates")
        }
        if case .github = entry.kind { return String(localized: "Install from GitHub") }
        switch session.state(for: entry) {
        case .available:
            return entry.raycastCopy == nil ? String(localized: "Install") : String(localized: "Import")
        case .installing: return String(localized: "Installing…")
        case .installed: return String(localized: "Open")
        case .updateAvailable: return String(localized: "Update")
        case .updating: return String(localized: "Updating…")
        }
    }

    func hasPrimaryAction(at selection: Int) -> Bool { true }

    func isPrimaryActionEnabled(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return !session.isChecking }
        if case .github = entry.kind { return true }
        switch session.state(for: entry) {
        case .available: return entry.listing != nil || entry.raycastCopy != nil
        case .installed, .updateAvailable: return true
        case .installing, .updating: return false
        }
    }

    func activate(at selection: Int) {
        guard isPrimaryActionEnabled(at: selection) else { return }
        guard let entry = entry(at: selection) else { return checkForUpdates() }
        if case .github(let source) = entry.kind {
            return core.extensionCoordinator.confirmInstallFromGitHub(source)
        }
        switch session.state(for: entry) {
        case .available:
            if let copy = entry.raycastCopy { session.importFromRaycast([copy]) } else { session.install(entry) }
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
        let entry = entry(at: selection)
        var items = entry.map(entryItems) ?? []
        let hasEntryItems = !items.isEmpty
        let first = items.count
        items.append(contentsOf: storeItems)
        if hasEntryItems, items.indices.contains(first) { items[first].startsSection = true }
        return PopoverMenuContent(header: entry?.title ?? String(localized: "Store"), items: items)
    }

    private func entryItems(_ entry: Entry) -> [PopoverMenuItem] {
        if case .github(let source) = entry.kind {
            return [
                PopoverMenuItem(
                    title: String(localized: "Install from GitHub"), systemImage: "hammer", shortcut: "↵"
                ) { core.extensionCoordinator.confirmInstallFromGitHub(source) }
            ]
        }
        let state = session.state(for: entry)
        var items: [PopoverMenuItem] = []
        switch state {
        case .available:
            if let copy = entry.raycastCopy {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Import"), systemImage: "arrow.down.doc", shortcut: "↵"
                    ) { session.importFromRaycast([copy]) })
            } else {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Install"), systemImage: "arrow.down.circle",
                        isEnabled: entry.listing != nil, shortcut: "↵"
                    ) { session.install(entry) })
            }
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
        return items
    }

    /// What Settings → Extensions does for the whole library, for ⌘K on any row or none.
    private var storeItems: [PopoverMenuItem] {
        let coordinator = core.extensionCoordinator
        var items = [
            PopoverMenuItem(
                title: String(localized: "Check for Updates"), systemImage: "arrow.clockwise",
                isEnabled: !session.isChecking
            ) { checkForUpdates() }
        ]
        if session.pendingUpdateCount > 0 {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Update All"), systemImage: "arrow.down.circle",
                    isEnabled: !session.isUpdating
                ) { session.updateAll() })
        }
        if !session.raycastPending.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Import All from Raycast"), systemImage: "arrow.down.doc"
                ) { session.importAllFromRaycast() })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Import from Raycast"), systemImage: "arrow.down.doc",
                isEnabled: session.raycastAvailable
            ) { session.setFilter(.raycast) })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Add from Folder…"), systemImage: "folder"
            ) { coordinator.addExtensionsFromFolders() })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Extension Settings…"), systemImage: "gearshape"
            ) { coordinator.showExtensionSettings() })
        return items
    }

    private func checkForUpdates() {
        Task {
            let count = await session.checkForUpdates()
            core.showMessage(
                count == 0
                    ? String(localized: "Everything is up to date")
                    : String(localized: "\(count) updates available"))
        }
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
            width: 0, fieldNames: [], firstIncompleteField: nil,
            optionsMenu: { field in field == Self.filterField ? filterMenu : nil },
            placement: .trailing,
            view: AnyView(
                HeaderMenuButton(
                    title: session.category.map(ExtensionStoreSession.title(ofCategory:))
                        ?? session.filter.title,
                    systemImage: session.category == nil ? session.filter.systemImage : "tag",
                    isOpen: false, help: String(localized: "Filter extensions  ⌘P"),
                    action: { openArgumentOptions(Self.filterField) })))
    }

    /// The menu row it opens on: the active category, else the active filter.
    var filterHighlight: Int {
        let filters = ExtensionStoreSession.Filter.allCases
        if let category = session.category,
            let index = ExtensionStoreResponse.categories.firstIndex(of: category)
        {
            return filters.count + index
        }
        return filters.firstIndex(of: session.filter) ?? 0
    }

    /// The filters, then the store's categories; All is the way back to the whole list.
    private var filterMenu: PopoverMenuContent {
        let filters = ExtensionStoreSession.Filter.allCases.map { filter in
            let isChosen = session.filter == filter && (filter != .all || session.category == nil)
            return PopoverMenuItem(
                title: filter.title, icon: isChosen ? .symbol("checkmark") : .blank
            ) {
                session.setFilter(filter)
                if filter == .all { session.setCategory(nil) }
                vm.selection = 0
            }
        }
        let categories = ExtensionStoreResponse.categories.enumerated().map { index, name in
            let isChosen = session.category == name
            return PopoverMenuItem(
                title: ExtensionStoreSession.title(ofCategory: name),
                icon: isChosen ? .symbol("checkmark") : .blank,
                sectionTitle: index == 0 ? String(localized: "Categories") : nil,
                startsSection: index == 0
            ) {
                session.setCategory(isChosen ? nil : name)
                vm.selection = 0
            }
        }
        return PopoverMenuContent(header: nil, items: filters + categories)
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
                },
                onCategory: { name in
                    session.browseCategory(name)
                    vm.selection = 0
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
