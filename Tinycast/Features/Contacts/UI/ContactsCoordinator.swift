import AppKit

/// Owns the opt-in, the Search Contacts command and what a card's actions do.
@MainActor
@Observable
final class ContactsCoordinator {
    let session: ContactsSession
    private let store: ContactStore
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    /// Dialogs and the HUD, so both stay owned by `AppCore`.
    private unowned let core: AppCore

    init(
        appIndex: AppIndex, settings: AppSettings, paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        let store = ContactStore()
        self.store = store
        session = ContactsSession(store: store)
        self.appIndex = appIndex
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    var access: ContactsAccess { store.access }

    /// TCC sends nothing when a grant changes in Settings, so a pane showing it re-reads.
    func refreshAccess() { store.refreshAccess() }

    // MARK: - Feature switch

    /// The switch funnels here so enabling, which is also consent, confirms first.
    func setContactsEnabled(_ enabled: Bool) {
        if !enabled {
            guard settings.contactsEnabled else { return }
            settings.contactsEnabled = false
            return
        }

        // Asking again is the only way back: Settings cannot add an app TCC has no record of.
        store.refreshAccess()
        guard !settings.contactsEnabled || store.access != .granted else { return }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Enable contacts?"),
                    message: String(
                        localized: """
                            Tinycast reads your contacts to search them and reach people from the \
                            launcher. It never changes them, and nothing leaves this Mac.
                            """),
                    symbol: "person.crop.circle", confirmTitle: String(localized: "Continue"),
                    tone: .neutral, confirmRole: .standard)
            else { return }

            guard await store.requestAccess() else { return }
            // The flag is consent, so it is written only once macOS has actually granted access.
            settings.contactsEnabled = true
            applyEnabled()
        }
    }

    func applyEnabled() {
        appIndex.setCommandsVisible([.searchContacts], settings.contactsEnabled)
        if !settings.contactsEnabled { session.end() }
    }

    // MARK: - Commands

    func showContacts() {
        store.refreshAccess()
        guard settings.contactsEnabled, store.access == .granted else {
            paletteCoordinator.hidePalette(restoreFocus: false)
            core.showMessage(String(localized: "Turn Contacts on in Settings first"), tone: .neutral)
            return
        }
        paletteCoordinator.togglePalette(mode: .contacts)
    }

    // MARK: - Row actions

    func copy(_ text: String, message: String = String(localized: "Copied text")) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(text)
        core.showMessage(message)
    }

    func open(_ url: URL?) {
        guard let url else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(url)
    }

    func openInContacts(_ contact: Contact) {
        open(ContactFormat.contactsURL(id: contact.id))
    }
}
